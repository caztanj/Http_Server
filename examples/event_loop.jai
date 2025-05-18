main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error then return;

    quit := false;
    while !quit {
        events, error := http_server_update(*server);
        if error then quit = true;

        for events {
            if #complete it.type == {
                case .Http_Request;
                    handle_request(*server, it.http_request);

                case .Web_Socket_Message;
                    handle_web_socket_message(it.web_socket_message);

                case .Close;
                    handle_close(it.close_event);
            }
        }

        reset_temporary_storage();
    }

    shutdown(*server);

    report_memory_leaks();
}

handle_request :: (server: *Http_Server, request: *Http_Request) {
    if is_web_socket_upgrade(request) {
        error := perform_web_socket_upgrade(server, request);
        if error {
            response := make_response(request,, temp);

            not_found(server, response);
            send_response(server, response);
        }
    } else {
        response := make_response(request,, temp);

        html(server, response, "<html>Hello</html>");
        send_response(server, response);
    }
}

handle_web_socket_message :: (message: Web_Socket_Message) {
    print("%\n", message.frame.payload.(string));
}

handle_close :: (close_event: Http_Close_Event) {
    print("% closed\n", close_event.id);
}

#import "Basic" () (MEMORY_DEBUGGER = true, TEMP_ALLOCATOR_POISON_FREED_MEMORY = true);
#import,file "../module.jai" () (ENABLE_TLS = true);