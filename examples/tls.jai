main :: () {
    server: Http_Server;

    error := init(*server, 3000, tls = true, certificate_file = "cert.pem", private_key_file = "key.pem");
    if error then return;

    quit := false;
    while !quit {
        error, events := http_server_update(*server);
        if error then quit = true;

        for events {
            if it.type != .Http_Request then continue;

            response := make_response(it,, temp);
            html(*server, response, "<html>TLS!</html>");
            send_response(*server, response);
        }

        reset_temporary_storage();
    }

    shutdown(*server);
}

#import "Basic";
#import,file "../module.jai";