main :: () {
    http_server: Http_Server;

    error := init(*http_server, 3000);
    if error then return;

    quit := false;
    while !quit {
        messages, error := http_server_update(*http_server);
        if error then quit = true;

        for messages {
            if #complete it.type == {
                case .Http;
                    if is_websocket_upgrade(*it.http_request) {
                        error := perform_websocket_upgrade(*it.http_request);
                        if error {
                            response := get_response(*it.http_request);
                            not_found(response);
                            send_response(response);
                        }
                    } else {
                        response := get_response(*it.http_request);
                        html(response, "<html>WebSocket</html>");
                        send_response(response);
                    }

                case .Web_Socket;
                    print("%\n", it.web_socket_message.frame);
            }
        }

        reset_temporary_storage();
    }

    shutdown(*http_server);
}

#import "Basic";
#import,file "../module.jai" () (ENABLE_TLS = true);