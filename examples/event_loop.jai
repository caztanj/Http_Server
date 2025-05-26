main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error then return;

    quit := false;
    while !quit {
        error, events := http_server_update(*server);
        if error then quit = true;

        for events {
            if #complete it.type == {
                case .Http_Request;
                    handle_request(*server, it);

                case .Web_Socket_Message;
                    handle_web_socket_message(it);

                case .Close;
                    handle_close(it);
            }
        }

        reset_temporary_storage();
    }

    shutdown(*server);

    report_memory_leaks();
}

handle_request :: (server: *Http_Server, event: Http_Event) {
    if is_web_socket_upgrade(event) {
        error := perform_web_socket_upgrade(server, event);
        if error {
            response := make_response(event,, temp);

            not_found(server, response);
            send_response(server, response);
        }
    } else {
        response := make_response(event,, temp);

        html(server, response, "<html>Hello</html>");
        send_response(server, response);
    }
}

handle_web_socket_message :: (event: Http_Event) {
    print("%\n", event.web_socket_message.frame.payload.(string));
}

handle_close :: (event: Http_Event) {
    print("% closed\n", event.client_socket);
}

#import "Basic" () (MEMORY_DEBUGGER = true, TEMP_ALLOCATOR_POISON_FREED_MEMORY = true);
#import,file "../module.jai" () (ENABLE_TLS = true);