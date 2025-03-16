main :: () {
    http_server: Http_Server;

    error := init(*http_server, 3000);
    if error then return;

    quit := false;
    while !quit {
        requests, error := http_server_update(*http_server);
        if error then quit = true;

        for requests {
            response := get_response(it);
            html(response, "<html>Hello</html>");
            send_response(response);
        }

        reset_temporary_storage();
    }

    shutdown(*http_server);
}

#import "Basic";
#import,file "../module.jai";