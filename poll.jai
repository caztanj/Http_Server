send_response :: (server: *Http_Server, response: *Http_Response) -> error: bool {
    client := find_client(server, response.id);
    if client == null then return true;

    assert(response.status != .None);

    b: String_Builder;
    b.allocator = temp;

    append(*b, tprint("HTTP/1.1 %\r\n", response_status_to_string(response.status)));

    for response.headers {
        append(*b, tprint("%: %\r\n", it.key, it.value));
    }

    append(*b, "\r\n");
    append(*b, response.body);

    serialized := builder_to_string(*b,, temp);

    done := false;
    while !done {
        chunk := array_add(*client.chunks_to_send);
        count := min(chunk.buffer.count, serialized.count);

        memcpy(chunk.buffer.data, serialized.data, count);

        chunk.bytes_to_send = count;

        serialized.data += count;
        serialized.count -= count;

        done = serialized.count == 0;
    }

    send_data_to_client(server, client);

    return false;
}

#scope_module

accept_clients :: (server: *Http_Server) {
    while true {
        #if OS == .WINDOWS {
            socket := Socket.accept(server.socket);
        } else {
            socket := Socket.accept_v6(server.socket);
        }

        if socket == Socket.INVALID_SOCKET {
            error := Socket.get_last_socket_error();
            if error == Socket.SOCKET_WOULDBLOCK then return;
            continue;
        }

        client := add_client(server, socket);

        #if ENABLE_TLS {
            if server.tls {
                client.ssl = LibreSSL.SSL_new(server.ssl_ctx);

                LibreSSL.SSL_set_fd(client.ssl, xx socket);

                result := LibreSSL.SSL_accept(client.ssl);
                if result <= 0 {
                    error := LibreSSL.SSL_get_error(client.ssl, result);
                    if error != LibreSSL.SSL_ERROR_WANT_READ && error != LibreSSL.SSL_ERROR_WANT_WRITE {
                        print_ssl_errors();
                        close(server, client);
                        continue;
                    }
                }
            }
        }

        success := Socket.set_blocking(socket, false);
        if !success {
            close(server, client);
            continue;
        }

        read_data_from_client(server, client, add = true);
    }
}

recv :: (server: *Http_Server, client: *Http_Client, buffer: *u8, size: int) -> int {
    #if ENABLE_TLS {
        if server.tls {
            return LibreSSL.SSL_read(client.ssl, buffer, xx size);
        }
    }

    return Socket.recv(client.socket, buffer, xx size, 0);
}

read_from_client :: (server: *Http_Server, client: *Http_Client) {
    while true {
        offset := client.request.raw.data + client.request.raw_count;
        max    := client.request.raw.count - client.request.raw_count;

        bytes_read := recv(server, client, offset, max);
        if bytes_read == -1 {
            error := Socket.get_last_socket_error();

            #if ENABLE_TLS {
                if server.tls {
                    if LibreSSL.SSL_get_error(client.ssl, xx bytes_read) == {
                        case LibreSSL.SSL_ERROR_WANT_READ;   #through;
                        case LibreSSL.SSL_ERROR_WANT_WRITE;  error = Socket.SOCKET_WOULDBLOCK;
                    }
                }
            }

            if error != Socket.SOCKET_WOULDBLOCK {
                close(server, client);
                return;
            }

            set_timeout(client, 30);
            return;
        }

        if bytes_read == 0 {
            close(server, client);
            return;
        }

        client.request.raw_count += bytes_read;

        if client.request.raw_count == MAX_REQUEST_SIZE {
            close(server, client);
            return;
        }

        set_timeout(client, 30);
    }
}

send :: (server: *Http_Server, client: *Http_Client, buffer: *u8, size: int) -> int {
    #if ENABLE_TLS {
        if server.tls {
            return LibreSSL.SSL_write(client.ssl, buffer, xx size);
        }
    }

    return Socket.send(client.socket, buffer, xx size, 0);
}

send_to_client :: (server: *Http_Server, client: *Http_Client) {
    assert(client.chunks_to_send.count > 0);
    chunk := *client.chunks_to_send[0];

    while chunk.bytes_to_send - chunk.bytes_sent > 0 {
        offset := chunk.buffer.data + chunk.bytes_sent;
        max    := chunk.bytes_to_send - chunk.bytes_sent;

        bytes_sent := send(server, client, offset, max);
        if bytes_sent == -1 {
            error := Socket.get_last_socket_error();

            #if ENABLE_TLS {
                if LibreSSL.SSL_get_error(client.ssl, xx bytes_sent) == {
                    case LibreSSL.SSL_ERROR_WANT_READ;   #through;
                    case LibreSSL.SSL_ERROR_WANT_WRITE;  error = Socket.SOCKET_WOULDBLOCK;
                }
            }

            if error != Socket.SOCKET_WOULDBLOCK {
                close(server, client);
                return;
            }

            set_timeout(client, 30);
            return;
        }

        chunk.bytes_sent += bytes_sent;

        set_timeout(client, 30);
    }

    if chunk.bytes_to_send - chunk.bytes_sent == 0 {
        array_ordered_remove_by_index(*client.chunks_to_send, 0);

        if client.chunks_to_send.count > 0 {
            send_to_client(server, client);
            return;
        }

        if client.close_after_send {
            close(server, client);
            return;
        }

        client.request.uri = "";
        client.request.method = .GET;
        client.request.body = "";
        array_reset(*client.request.headers);

        if client.phase != .Web_Socket {
            if client.request.t < client.request.max_t {
                count := client.request.max_t - client.request.t;
                memcpy(client.request.raw.data, client.request.t, count);
                client.request.raw_count = count;
            } else {
                client.request.raw_count = 0;
            }
        }

        if client.phase == .Upgrading_To_Web_Socket {
            client.phase = .Web_Socket;
        }

        read_data_from_client(server, client);
    }
}

process_timeouts_and_get_next_timeout :: (server: *Http_Server) -> int {
    if server.clients.count == 0 then return -1;

    now := current_time_monotonic();
    earliest := -1;

    for server.clients {
        if it.timeout <= now {
            // @Todo: If this is a web socket we want to send a close frame.
            close(server, it);
            continue;
        }

        this := to_milliseconds(it.timeout - now);

        if earliest == -1 || this < earliest then earliest = this;
    }

    return earliest;
}