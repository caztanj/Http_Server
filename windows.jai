init :: (server: *Http_Server, port: u16, tls := false, certificate_file := "", private_key_file := "") -> error: bool {
    assert(!tls);

    Socket.socket_init();

    server.socket = Socket.socket(Socket.AF_INET, .SOCK_STREAM, Socket.IPPROTO.IPPROTO_TCP);
    if server.socket == Socket.INVALID_SOCKET then return true;

    result := Socket.bind(server.socket, Socket.INADDR_ANY, port);
    if result != 0 then return true;

    result = Socket.listen(server.socket, Socket.SOMAXCONN);
    if result != 0 then return true;

    success := Socket.set_blocking(server.socket, false);
    if !success then return true;

    poll_add(server, server.socket, Socket.POLLIN);

    server.tls = tls;

    return false;
}

shutdown :: (server: *Http_Server) {
    for * server.clients {
        close(it);
        fini(it);
    }

    array_reset(*server.events);
    bucket_array_reset(*server.clients);
}

http_server_update :: (server: *Http_Server) -> [] *Http_Request, error: bool #must {
    results: [..] *Http_Request;
    results.allocator = temp;

    timeout := process_timeouts_and_get_next_timeout(server);

    nevents := Socket.WSAPoll(server.events.data, xx server.events.count, xx timeout);
    if nevents == Socket.SOCKET_ERROR then return .[], true;

    for server.events {
        if it.fd == server.socket {
            accept_clients(server);
            continue;
        }

        client := find_client(server, it.fd);
        assert(client != null);

        if it.revents & Socket.POLLIN {
            request := read_from_client(client);
            if request {
                array_add(*results, request);
            }

            continue;
        }

        if it.revents & Socket.POLLOUT {
            send_to_client(client);
            continue;
        }
    }

    return results, false;
}

send_response :: (response: *Http_Response) {
    assert(response.status != .None);

    b: String_Builder;
    b.allocator = temp;

    if response.client.close_after_send {
        set_header(*response.headers, "Connection", "close");
    } else {
        set_header(*response.headers, "Connection", "keep-alive");
        set_header(*response.headers, "Keep-Alive", "timeout=30"); // @Todo: Make this configurable.
    }

    set_header(*response.headers, "Content-Length", tprint("%", response.body.count));

    append(*b, tprint("HTTP/1.1 %\r\n", response_status_to_string(response.status)));

    for response.headers {
        append(*b, tprint("%: %\r\n", it.key, it.value));
    }

    append(*b, "\r\n");
    append(*b, response.body);

    response.serialized = builder_to_string(*b,, response.client.allocator);

    poll_mod(response.client.server, response.client.socket, Socket.POLLOUT);
}

Http_Server :: struct {
    socket: Socket.Socket;

    tls: bool;

    events:  [..] Socket.WSAPOLLFD;
    clients: Bucket_Array(Http_Client, 1024);
}

#scope_module

poll_add :: (server: *Http_Server, fd: Socket.Socket, events: s16) {
    pollfd := Socket.WSAPOLLFD.{ fd = fd, events = events };
    array_add(*server.events, pollfd);
}

poll_mod :: (server: *Http_Server, fd: Socket.Socket, events: s16) {
    for * server.events {
        if it.fd == fd {
            it.events = events;
            break;
        }
    }
}

accept_clients :: (server: *Http_Server) {
    while true {
        socket := Socket.accept(server.socket);
        if socket == Socket.INVALID_SOCKET {
            error := Socket.get_last_socket_error();
            if error == Socket.SOCKET_WOULDBLOCK then return;
            continue;
        }

        client := add_client(server, socket);

        success := Socket.set_blocking(socket, false);
        if !success {
            close(client);
            continue;
        }

        poll_add(server, socket, Socket.POLLIN);
    }
}

read_from_client :: (client: *Http_Client) -> *Http_Request {
    while true {
        offset := client.request.raw.data + client.request.raw_count;
        max    := client.request.raw.count - client.request.raw_count;

        bytes_read := Socket.recv(client.socket, offset, xx max, 0);
        if bytes_read == -1 {
            error := Socket.get_last_socket_error();
            if error != Socket.SOCKET_WOULDBLOCK {
                close(client);
                return null;
            }

            set_timeout(client, 30);
            return null;
        }

        if bytes_read == 0 {
            close(client);
            return null;
        }

        client.request.raw_count += bytes_read;

        if client.request.raw_count == MAX_REQUEST_SIZE {
            close(client);
            return null;
        }

        status := parse_request(client);
        if #complete status == {
            case .Error;
                close(client);
                return null;

            case .Need_More_Data;
                continue;

            case .Success;
                client.handed_off_to_main_loop = true;
                return *client.request;
        }

        set_timeout(client, 30);
    }

    return null;
}

send_to_client :: (client: *Http_Client) {
    client.handed_off_to_main_loop = false;
    if client.close {
        close(client);
        return;
    }

    while client.response.serialized.count - client.response.bytes_sent > 0 {
        offset := client.response.serialized.data + client.response.bytes_sent;
        max    := client.response.serialized.count - client.response.bytes_sent;

        bytes_sent := Socket.send(client.socket, offset, xx max, 0);
        if bytes_sent == -1 {
            error := Socket.get_last_socket_error();
            if error != Socket.SOCKET_WOULDBLOCK {
                close(client);
                return;
            }

            set_timeout(client, 30);
            return;
        }

        client.response.bytes_sent += bytes_sent;

        set_timeout(client, 30);
    }

    if client.response.serialized.count - client.response.bytes_sent == 0 {
        if client.close_after_send {
            close(client);
            return;
        }

        reset(client);
        poll_mod(client.server, client.socket, Socket.POLLIN);
    }
}

close :: (client: *Http_Client) {
    if client.handed_off_to_main_loop {
        client.close = true;
        return;
    }

    for client.server.events {
        if it.fd == client.socket {
            remove it;
            break;
        }
    }

    Socket.close_and_reset(*client.socket);
    fini(*client.pool);
    remove_client(client);
}

process_timeouts_and_get_next_timeout :: (server: *Http_Server) -> int {
    if server.clients.count == 0 then return -1;

    now := current_time_monotonic();
    earliest := -1;

    for * server.clients {
        if it.timeout <= now {
            close(it);
            continue;
        }

        this := to_milliseconds(it.timeout - now);

        if earliest == -1 || this < earliest then earliest = this;
    }

    return earliest;
}