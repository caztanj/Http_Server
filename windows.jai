init :: (server: *Http_Server, port: u16, tls := false, certificate_file := "", private_key_file := "") -> error: bool {
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

    if tls {
        server.ssl_ctx = create_context();
        if server.ssl_ctx == null then return true;

        error := configure_context(server.ssl_ctx, certificate_file, private_key_file);
        if error then return true;
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

    array_reset(*server.events);
    deinit(*server.clients);
}

http_server_update :: (server: *Http_Server, peek := false) -> error: bool, [] Http_Event {
    events: [..] Http_Event;
    events.allocator = temp;

    timeout := process_timeouts_and_get_next_timeout(server);

    nevents := Socket.WSAPoll(server.events.data, xx server.events.count, xx ifx peek then 0 else timeout);
    if nevents == Socket.SOCKET_ERROR then return true, .[];

    for server.events {
        if it.fd == server.socket {
            accept_clients(server);
            continue;
        }

        client := find_client(server, it.fd);
        assert(client != null);

        if it.revents & Socket.POLLHUP {
            close(server, client);
            continue;
        }

        if it.revents & Socket.POLLIN {
            closed := read_from_client(server, client);
            if closed then continue;

            while maybe_parse_request_or_web_socket_message(server, it.fd, *events) {}
        }

        if it.revents & Socket.POLLOUT {
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
    socket: Socket.Socket;

    tls: bool;

    ssl_ctx: *LibreSSL.SSL_CTX;

    events:  [..] Socket.WSAPOLLFD;
    clients: Table(Socket.Socket, *Http_Client);

    closed_sockets: [..] Socket.Socket;
    closed_sockets.allocator = temp;
}

#scope_module

read_data_from_client :: (server: *Http_Server, client: *Http_Client, $add := false) {
    #if add {
        poll_add(server, client.socket, Socket.POLLIN);
    } else {
        poll_mod(server, client.socket, Socket.POLLIN);
    }
}

send_data_to_client :: (server: *Http_Server, client: *Http_Client) {
    poll_mod(server, client.socket, Socket.POLLOUT);
}

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

close :: (server: *Http_Server, client: *Http_Client, gracefully := false) {
    if gracefully && client.chunks_to_send.count > 0 {
        client.close_after_send = true;
        return;
    }

    for server.events {
        if it.fd == client.socket {
            remove it;
            break;
        }
    }

    if server.tls {
        LibreSSL.SSL_shutdown(client.ssl);
        LibreSSL.SSL_free(client.ssl);
    }

    array_add(*server.closed_sockets, client.socket);

    socket := client.socket;
    Socket.close_and_reset(*socket);
    remove_client(server, client);
}