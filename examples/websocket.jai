main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error then return;

    quit := false;
    while !quit {
        requests, error, web_socket_events := http_server_update(*server);
        if error then quit = true;

        for requests {
            if is_web_socket_upgrade(it) {
                error := perform_web_socket_upgrade(*server, it);
                if error {
                    response := make_response(it,, temp);

                    not_found(*server, response);
                    send_response(*server, response);
                }
            } else {
                response := make_response(it,, temp);

                html(*server, response, "<html>Web Socket</html>");
                send_response(*server, response);
            }
        }

        for web_socket_events {
            print("%\n", cast(string) it.frame.payload);
            send_web_socket_text(*server, it.client_id, "Hello from Jai!");
        }

        reset_temporary_storage();
    }

    shutdown(*server);

    report_memory_leaks();
}

#import "Basic" () (MEMORY_DEBUGGER = true, TEMP_ALLOCATOR_POISON_FREED_MEMORY = true);
#import,file "../module.jai" () (ENABLE_TLS = true);