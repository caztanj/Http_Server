init :: (server: *Http_Server, port: u16, tls := false, certificate_file := "", private_key_file := "") -> error: bool {
    POSIX.signal(POSIX.SIGPIPE, POSIX.SIG_IGN);

    server.epoll = Linux.epoll_create1(0);
    if server.epoll == -1 then return true;

    server.socket = Socket.socket(Socket.AF_INET6, .SOCK_STREAM, Socket.IPPROTO.IPPROTO_TCP);
    if server.socket == Socket.INVALID_SOCKET then return true;

    options := 1;
    result := Socket.setsockopt(server.socket, Socket.SOL_SOCKET, Socket.SO_REUSEPORT, *options, size_of(type_of(options)));
    if result == -1 then return true;

    // On Linux we can use both IPv4 and IPv6 if we open an IPv6 socket. This behaviour can be turned off with these 2 lines:
    // enable := 1;
    // result = Socket.setsockopt(server.socket, xx Socket.IPPROTO.IPPROTO_IPV6, Socket.IPV6_V6ONLY, *enable, size_of(type_of(enable)));

    result = Socket.bind(server.socket, Socket.in6addr_any.__in6_u.__u6_addr8, port);
    if result != 0 then return true;

    result = Socket.listen(server.socket, Socket.SOMAXCONN);
    if result != 0 then return true;

    success := Socket.set_blocking(server.socket, false);
    if !success then return true;

    error := epoll_add(server.epoll, server.socket, Linux.EPOLLIN);
    if error then return true;

    mask: POSIX.sigset_t;
    POSIX.sigemptyset(*mask);
    POSIX.sigaddset(*mask, POSIX.SIGINT);
    POSIX.sigprocmask(POSIX.SIG_BLOCK, *mask, null);
    server.sigint = POSIX.signalfd(-1, *mask, xx POSIX.SFD.CLOEXEC);
    if server.sigint == -1 then return true;

    error = epoll_add(server.epoll, server.sigint, Linux.EPOLLIN);
    if error then return true;

    #if ENABLE_TLS {
        if tls {
            server.ssl_ctx = create_context();
            if server.ssl_ctx == null then return true;

            error = configure_context(server.ssl_ctx, certificate_file, private_key_file);
            if error then return true;
        }
    }

    server.tls = tls;

    return false;
}

shutdown :: (server: *Http_Server) {
    for * server.clients {
        close(it);
        fini(it);
    }

    #if ENABLE_TLS {
        if server.tls {
            SSL_CTX_free(server.ssl_ctx);
        }
    }

    bucket_array_reset(*server.clients);
}

http_server_update :: (server: *Http_Server) -> [] *Http_Request, error: bool #must {
    results: [..] *Http_Request;
    results.allocator = temp;

    timeout := process_timeouts_and_get_next_timeout(server);

    events: [1024] Linux.epoll_event;
    nfds := Linux.epoll_wait(server.epoll, events.data, events.count, xx timeout);
    if nfds == -1 then return .[], true;

    for i: 0..nfds - 1 {
        ev := events[i];

        if ev.data.fd == server.socket {
            accept_clients(server);
            continue;
        }

        if ev.data.fd == server.sigint then return .[], true;

        client := find_client(server, ev.data.fd);
        assert(client != null);

        if ev.events & Linux.EPOLLIN {
            request := read_from_client(client);
            if request {
                array_add(*results, request);
            }

            continue;
        }

        if ev.events & Linux.EPOLLOUT {
            send_to_client(client);
            continue;
        }

        // @Todo: Handle other epoll events.
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

    epoll_mod(response.client.server.epoll, response.client.socket, Linux.EPOLLET | Linux.EPOLLOUT);
}

Http_Server :: struct {
    epoll: s32;
    socket: Socket.Socket;

    sigint: s32;

    tls: bool;

    #if ENABLE_TLS {
        ssl_ctx: *SSL_CTX;
    }

    // @Todo: Should we use a bucket array or a table?
    clients: Bucket_Array(Http_Client, 1024);
}

#scope_module

epoll_add :: (epoll: s32, fd: s32, events: u32) -> error: bool {
    ev: Linux.epoll_event;
    ev.events = events;
    ev.data.fd = fd;

    result := Linux.epoll_ctl(epoll, .ADD, fd, *ev);
    return result == -1;
}

epoll_mod :: (epoll: s32, fd: s32, events: u32) -> error: bool {
    ev: Linux.epoll_event;
    ev.events = events;
    ev.data.fd = fd;

    result := Linux.epoll_ctl(epoll, .MOD, fd, *ev);
    return result == -1;
}

accept_clients :: (server: *Http_Server) {
    while true {
        socket := Socket.accept_v6(server.socket);
        if socket == Socket.INVALID_SOCKET {
            error := Socket.get_last_socket_error();
            if error == Socket.SOCKET_WOULDBLOCK then return;
            continue;
        }

        client := add_client(server, socket);

        #if ENABLE_TLS {
            if server.tls {
                client.ssl = SSL_new(server.ssl_ctx);

                SSL_set_fd(client.ssl, socket);

                if SSL_accept(client.ssl) <= 0 {
                    ERR_print_errors_fp(POSIX.stderr);
                    close(client);
                    continue;
                }
            }
        }

        success := Socket.set_blocking(socket, false);
        if !success {
            close(client);
            continue;
        }

        error := epoll_add(server.epoll, socket, Linux.EPOLLET | Linux.EPOLLIN);
        if error {
            close(client);
            continue;
        }
    }
}

recv :: (client: *Http_Client, buffer: *u8, size: int) -> int {
    #if ENABLE_TLS {
        if client.server.tls {
            return SSL_read(client.ssl, buffer, xx size);
        }
    }

    return Socket.recv(client.socket, buffer, xx size, 0);
}

read_from_client :: (client: *Http_Client) -> *Http_Request {
    while true {
        offset := client.request.raw.data + client.request.raw_count;
        max    := client.request.raw.count - client.request.raw_count;

        bytes_read := recv(client, offset, max);
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

send :: (client: *Http_Client, buffer: *u8, size: int) -> int {
    #if ENABLE_TLS {
        if client.server.tls {
            return SSL_write(client.ssl, buffer, xx size);
        }
    }

    return Socket.send(client.socket, buffer, xx size, 0);
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

        bytes_sent := send(client, offset, max);
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
        epoll_mod(client.server.epoll, client.socket, Linux.EPOLLET | Linux.EPOLLIN);
    }
}

close :: (client: *Http_Client) {
    if client.handed_off_to_main_loop {
        client.close = true;
        return;
    }

    #if ENABLE_TLS {
        if client.server.tls {
            SSL_shutdown(client.ssl);
            SSL_free(client.ssl);
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
