main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error {
        log_error("Failed to init server.");
        exit(1);
    }

    while true {
        error, events := http_server_update(*server);
        if error {
            log_error("http_server_update error.");
            exit(1);
        }

        for events {
            if it.type == .Http_Request {
                if is_web_socket_upgrade(it) {
                    error := perform_web_socket_upgrade(*server, it);
                    if error {
                        response := make_response(it,, temp);

                        internal_server_error(*server, response);
                        send_response(*server, response);
                    }
                } else {
                    log_error("Received an HTTP request.");
                    exit(1);
                }
            }

            if it.type == .Web_Socket_Message {
                if #complete it.web_socket_message.type == {
                    case .Ping;
                        send_web_socket_pong(*server, it);

                    case .Text;
                        send_web_socket_text(*server, it, cast(string) it.web_socket_message.frame.payload);

                    case .Binary;
                        send_web_socket_blob(*server, it, xx cast(string) it.web_socket_message.frame.payload);

                    case .Error;
                        fail_web_socket_connection(*server, it);
                }
            }
        }

        reset_temporary_storage();
    }
}

#import "Basic";
#import,file "../../module.jai" () (MAX_REQUEST_SIZE = 1_048_576 * 20);