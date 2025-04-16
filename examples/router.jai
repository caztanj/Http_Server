main :: () {
    http_server: Http_Server;

    error := init(*http_server, 3000);
    if error then return;

    router: Http_Router;
    init(*router);

    get(*router, "/", (request: *Http_Request, response: *Http_Response) {
        html(response, "/");
    });

    get(*router, "/hello", (request: *Http_Request, response: *Http_Response) {
        html(response, "/hello");
    });

    get(*router, "/a/b/c", (request: *Http_Request, response: *Http_Response) {
        html(response, "/a/b/c");
    });

    get(*router, "/a/d", (request: *Http_Request, response: *Http_Response) {
        html(response, "/a/d");
    });

    quit := false;
    while !quit {
        requests, error := http_server_update(*http_server);
        if error then quit = true;

        for requests {
            handled := http_router_handle_request(*router, it);
            if !handled {
                response := get_response(it);
                not_found(response);
                send_response(response);
            }
        }

        reset_temporary_storage();
    }

    fini(*router);
    shutdown(*http_server);
}

#import "Basic";
#import,file "../module.jai";