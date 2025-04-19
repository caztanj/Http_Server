main :: () {
    http_server: Http_Server;

    error := init(*http_server, 3000, tls = true, certificate_file = "cert.pem", private_key_file = "key.pem");
    if error then return;

    quit := false;
    while !quit {
        messages, error := http_server_update(*http_server);
        if error then quit = true;

        for messages {
            response := get_response(*it.http_request);
            html(response, "<html>TLS!</html>");
            send_response(response);
        }

        reset_temporary_storage();
    }

    shutdown(*http_server);
}

#import "Basic";
#import,file "../module.jai" () (ENABLE_TLS = true);