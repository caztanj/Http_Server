main :: () {
    server: Http_Server;

    error := init(*server, 3000, tls = true, certificate_file = "cert.pem", private_key_file = "key.pem");
    if error then return;

    quit := false;
    while !quit {
        requests, error := http_server_update(*server);
        if error then quit = true;

        for requests {
            response := make_response(it);
            html(*server, response, "<html>TLS!</html>");
            send_response(*server, response);
        }

        reset_temporary_storage();
    }

    shutdown(*server);
}

#import "Basic";
#import,file "../module.jai" () (ENABLE_TLS = true);