init :: (server: *Http_Server, port: u16, tls := false, certificate_file := "", private_key_file := "") -> error: bool {
    POSIX.signal(POSIX.SIGPIPE, POSIX.SIG_IGN);

    server.epoll = Linux.epoll_create1(0);
    if server.epoll == -1 return true;

    server.socket = Socket.socket(Socket.AF_INET6, .SOCK_STREAM, Socket.IPPROTO.IPPROTO_TCP);
    if server.socket == Socket.INVALID_SOCKET return true;

    options := 1;
    result := Socket.setsockopt(server.socket, Socket.SOL_SOCKET, Socket.SO_REUSEPORT, *options, size_of(type_of(options)));
    if result == -1 return true;

    // On Linux we can use both IPv4 and IPv6 if we open an IPv6 socket. This behaviour can be turned off with these 2 lines:
    // enable := 1;
    // result = Socket.setsockopt(server.socket, xx Socket.IPPROTO.IPPROTO_IPV6, Socket.IPV6_V6ONLY, *enable, size_of(type_of(enable)));

    result = Socket.bind(server.socket, Socket.in6addr_any.__in6_u.__u6_addr8, port);
    if result != 0 return true;

    result = Socket.listen(server.socket, Socket.SOMAXCONN);
    if result != 0 return true;

    success := Socket.set_blocking(server.socket, false);
    if !success return true;

    error := epoll_add(server.epoll, server.socket, Linux.EPOLLIN);
    if error return true;

    mask: POSIX.sigset_t;
    POSIX.sigemptyset(*mask);
    POSIX.sigaddset(*mask, POSIX.SIGINT);
    POSIX.sigprocmask(POSIX.SIG_BLOCK, *mask, null);
    server.sigint = POSIX.signalfd(-1, *mask, xx POSIX.SFD.CLOEXEC);
    if server.sigint == -1 return true;

    error = epoll_add(server.epoll, server.sigint, Linux.EPOLLIN);
    if error return true;

    if tls {
        server.ssl_ctx = create_context();
        if server.ssl_ctx == null return true;

        error = configure_context(server.ssl_ctx, certificate_file, private_key_file);
        if error return true;
    }

    server.tls = tls;

    return false;
}

shutdown :: (server: *Http_Server) {
    for server.clients {
        close(server, it);
    }

    if server.tls {
        LibreSSL.SSL_CTX_free(server.ssl_ctx);
    }

    deinit(*server.clients);
}

http_server_update :: (server: *Http_Server, peek := false) -> error: bool, [] Http_Event {
    events: [..] Http_Event;
    events.allocator = temp;

    timeout := process_timeouts_and_get_next_timeout(server);

    epoll_events: [1024] Linux.epoll_event;
    nfds := Linux.epoll_wait(server.epoll, epoll_events.data, epoll_events.count, xx ifx peek then 0 else timeout);
    if nfds == -1 return true, .[];

    for i: 0..nfds - 1 {
        ev := epoll_events[i];

        if ev.data.fd == server.socket {
            accept_clients(server);
            continue;
        }

        if ev.data.fd == server.sigint return true, .[];

        client := find_client(server, ev.data.fd);
        assert(client != null);

        error_events :: Linux.EPOLLPRI & Linux.EPOLLERR & Linux.EPOLLHUP;
        if ev.events & error_events {
            close(server, client);
            continue;
        }

        if ev.events & Linux.EPOLLIN {
            closed := read_from_client(server, client);
            if closed continue;

            while maybe_parse_request_or_web_socket_message(server, ev.data.fd, *events) {}
        }

        if ev.events & Linux.EPOLLOUT {
            while send_to_client(server, client) {}
        }
    }

    for server.closed_sockets {
        event := array_add(*events);
        event.type = .Close;
        event.client_socket = it;
    }

    array_reset_keeping_memory(*server.closed_sockets);

    return false, events;
}

Http_Server :: struct {
    epoll: s32;
    socket: Socket.Socket;

    sigint: s32;

    tls: bool;

    ssl_ctx: *LibreSSL.SSL_CTX;

    clients: Table(Socket.Socket, *Http_Client);

    closed_sockets: [..] Socket.Socket;
    closed_sockets.allocator = temp;
}

#scope_module

read_data_from_client :: (server: *Http_Server, client: *Http_Client, $add := false) {
    #if add {
        epoll_add(server.epoll, client.socket, Linux.EPOLLET | Linux.EPOLLIN);
    } else {
        epoll_mod(server.epoll, client.socket, Linux.EPOLLET | Linux.EPOLLIN);
    }
}

send_data_to_client :: (server: *Http_Server, client: *Http_Client) {
    epoll_mod(server.epoll, client.socket, Linux.EPOLLET | Linux.EPOLLOUT);
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

close :: (server: *Http_Server, client: *Http_Client, gracefully := false) {
    if gracefully && client.chunks_to_send.count > 0 {
        client.close_after_send = true;
        return;
    }

    if server.tls {
        LibreSSL.SSL_shutdown(client.ssl);
        LibreSSL.SSL_free(client.ssl);
    }

    for client.chunks_to_send {
        if it.file_fd != -1 POSIX.close(it.file_fd);
    }

    array_add(*server.closed_sockets, client.socket);

    socket := client.socket;
    Socket.close_and_reset(*socket);
    remove_client(server, client);
}

sendfile :: (out_fd: s32, in_fd: s32, offset: *POSIX.off_t, count: s32) -> s32 #foreign libc;