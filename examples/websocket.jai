main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error then return;

    quit := false;
    while !quit {
        events, error := http_server_update(*server);
        if error then quit = true;

        for events {
            if it.type == .Http_Request {
                if is_web_socket_upgrade(it.http_request) {
                    error := perform_web_socket_upgrade(*server, it.http_request);
                    if error {
                        response := make_response(it.http_request,, temp);

                        not_found(*server, response);
                        send_response(*server, response);
                    }
                } else {
                    response := make_response(it.http_request,, temp);

                    html(*server, response, "<html>Web Socket</html>");
                    send_response(*server, response);
                }
            }

            if it.type == .Web_Socket_Message {
                print("%\n", cast(string) it.web_socket_message.frame.payload);
                send_web_socket_text(*server, it.web_socket_message.client_id, "Hello from Jai!");
            }
        }

        reset_temporary_storage();
    }

    shutdown(*server);

    report_memory_leaks();
}

#import "Basic" () (MEMORY_DEBUGGER = true, TEMP_ALLOCATOR_POISON_FREED_MEMORY = true);
#import,file "../module.jai" () (ENABLE_TLS = true);