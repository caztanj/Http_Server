init :: (server: *Http_Server, port: u16, tls := false, certificate_file := "", private_key_file := "") -> error: bool {
    server.kqueue = Macos.kqueue();
    if server.kqueue == -1 then return true;

    server.socket = Socket.socket(Socket.AF_INET, .SOCK_STREAM, Socket.IPPROTO.IPPROTO_TCP);
    if server.socket == Socket.INVALID_SOCKET then return true;

    options := 1;
    result := Socket.setsockopt(server.socket, Socket.SOL_SOCKET, Socket.SO_REUSEPORT, *options, size_of(type_of(options)));
    if result == -1 then return true;

    result = Socket.bind(server.socket, Socket.INADDR_ANY, port);
    if result != 0 then return true;

    result = Socket.listen(server.socket, Socket.SOMAXCONN);
    if result != 0 then return true;

    success := Socket.set_blocking(server.socket, false);
    if !success then return true;

    kqueue_event(server, server.socket, .READ, .ADD | .ENABLE);

    #if ENABLE_TLS {
        if tls {
            server.ssl_ctx = create_context();
            if server.ssl_ctx == null then return true;

            error := configure_context(server.ssl_ctx, certificate_file, private_key_file);
            if error then return true;
        }
    }

    server.tls = tls;

    return false;
}

shutdown :: (server: *Http_Server) {
    server.shutdown = true;

    for server.clients {
        close(server, it);
    }

    #if ENABLE_TLS {
        if server.tls {
            LibreSSL.SSL_CTX_free(server.ssl_ctx);
        }
    }

    array_reset(*server.kqueue_changes);
    deinit(*server.clients);
}

http_server_update :: (server: *Http_Server) -> [] *Http_Request, error: bool #must, [] Web_Socket_Event {
    requests: [..] *Http_Request;
    requests.allocator = temp;

    web_socket_events: [..] Web_Socket_Event;
    web_socket_events.allocator = temp;

    timeout := process_timeouts_and_get_next_timeout(server);

    ts: POSIX.timespec;
    ts.tv_sec = ifx timeout == -1 then 0 else timeout;

    events: [1024] Macos.Kevent64;
    nfds := Macos.kevent64(server.kqueue, server.kqueue_changes.data, xx server.kqueue_changes.count, events.data, xx events.count, 0, ifx timeout == -1 then null else *ts);
    if nfds == -1 then return .[], true, .[];

    array_reset_keeping_memory(*server.kqueue_changes);

    for i: 0..nfds - 1 {
        ev := events[i];

        if ev.ident == xx server.socket {
            accept_clients(server);
            continue;
        }

        client := find_client(server, xx ev.ident);
        assert(client != null);

        if ev.filter == .READ {
            read_from_client(server, client);
        }

        if ev.filter == .WRITE {
            send_to_client(server, client);
        }

        maybe_parse_request_or_web_socket_message(server, xx ev.ident, *requests, *web_socket_events);
    }

    return requests, false, web_socket_events;
}

Http_Server :: struct {
    kqueue: s32;
    socket: Socket.Socket;

    tls: bool;

    #if ENABLE_TLS {
        ssl_ctx: *LibreSSL.SSL_CTX;
    }

    shutdown: bool;

    kqueue_changes: [..] Macos.Kevent64;
    clients: Table(Socket.Socket, *Http_Client);
}

#scope_module

read_data_from_client :: (server: *Http_Server, client: *Http_Client, $add := false) {
    #if add {
        kqueue_event(server, client.socket, .READ, .ADD | .ENABLE);
    } else {
        kqueue_event(server, client.socket, .READ);
    }
}

send_data_to_client :: (server: *Http_Server, client: *Http_Client) {
    kqueue_event(server, client.socket, .WRITE);
}

kqueue_event :: (server: *Http_Server, fd: s32, filter: Macos.Kevent_Filter, flags: Macos.Kevent_Flags = 0) {
    ev: Macos.Kevent64;
    ev.ident = xx fd;
    ev.filter = filter;
    ev.flags = flags;

    array_add(*server.kqueue_changes, ev);
}

close :: (server: *Http_Server, client: *Http_Client) {
    if client.handed_off_to_main_loop && !server.shutdown {
        client.close = true;
        return;
    }

    #if ENABLE_TLS {
        if server.tls {
            LibreSSL.SSL_shutdown(client.ssl);
            LibreSSL.SSL_free(client.ssl);
        }
    }

    socket := client.socket;
    Socket.close_and_reset(*socket);
    remove_client(server, client);
}