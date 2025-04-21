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
            LibreSSL.SSL_CTX_free(server.ssl_ctx);
        }
    }

    bucket_array_reset(*server.clients);
}

http_server_update :: (server: *Http_Server) -> [] *Message, error: bool #must {
    results: [..] *Message;
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
            message := read_from_client(client);
            if message {
                array_add(*results, message);
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

Http_Server :: struct {
    epoll: s32;
    socket: Socket.Socket;

    sigint: s32;

    tls: bool;

    #if ENABLE_TLS {
        ssl_ctx: *LibreSSL.SSL_CTX;
    }

    clients: Bucket_Array(Http_Client, 1024);
}

#scope_module

read_data_from_client :: (client: *Http_Client, $add := false) {
    #if add {
        epoll_add(client.server.epoll, client.socket, Linux.EPOLLET | Linux.EPOLLIN);
    } else {
        epoll_mod(client.server.epoll, client.socket, Linux.EPOLLET | Linux.EPOLLIN);
    }
}

send_data_to_client :: (client: *Http_Client) {
    epoll_mod(client.server.epoll, client.socket, Linux.EPOLLET | Linux.EPOLLOUT);
}

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

close :: (client: *Http_Client) {
    if client.handed_off_to_main_loop {
        client.close = true;
        return;
    }

    #if ENABLE_TLS {
        if client.server.tls {
            LibreSSL.SSL_shutdown(client.ssl);
            LibreSSL.SSL_free(client.ssl);
        }
    }

    Socket.close_and_reset(*client.socket);
    fini(*client.pool);
    remove_client(client);
}
