main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error then return;

    quit := false;
    while !quit {
        error, events := http_server_update(*server);
        if error then quit = true;

        for events {
            if it.type == {
                case .Http_Request;
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

                case .Web_Socket_Message;
                    if #complete it.web_socket_message.type == {
                        case .Ping;
                            send_web_socket_pong(*server, it);

                        case .Text;
                            print("%\n", cast(string) it.web_socket_message.frame.payload);
                            send_web_socket_text(*server, it, "Hello from Jai!");

                        case .Binary;
                            send_web_socket_blob(*server, it, cast([] u8) "Hello from Jai");

                        case .Error;
                            fail_web_socket_connection(*server, it);
                    }
            }
        }

        reset_temporary_storage();
    }

    shutdown(*server);

    report_memory_leaks();
}

#import "Basic" () (MEMORY_DEBUGGER = true, TEMP_ALLOCATOR_POISON_FREED_MEMORY = true);
#import,file "../module.jai";