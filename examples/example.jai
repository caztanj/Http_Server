main :: () {
    http_server: Http_Server;

    error := init(*http_server, 3000);
    if error then return;

    quit := false;
    while !quit {
        requests, error := http_server_update();

        for requests {
            response := get_response(it);
            html(response, "<html>Hello</html>");
            send_response(response);
        }

        reset_temporary_storage();
    }
}

#import "Basic";
#import,file "../module.jai";