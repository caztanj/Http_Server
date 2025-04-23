main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error then return;

    router: Http_Router;
    init(*router, *server);

    get(*router, "/", (server: *Http_Server, request: *Http_Request, response: *Http_Response) {
        html(server, response, "/");
    });

    get(*router, "/hello", (server: *Http_Server, request: *Http_Request, response: *Http_Response) {
        html(server, response, "/hello");
    });

    get(*router, "/a/b/c", (server: *Http_Server, request: *Http_Request, response: *Http_Response) {
        html(server, response, "/a/b/c");
    });

    get(*router, "/a/d", (server: *Http_Server, request: *Http_Request, response: *Http_Response) {
        html(server, response, "/a/d");
    });

    quit := false;
    while !quit {
        requests, error := http_server_update(*server);
        if error then quit = true;

        for requests {
            handled := http_router_handle_request(*server, *router, it);
            if !handled {
                response := make_response(it,, temp);
                not_found(*server, response);
                send_response(*server, response);
            }
        }

        reset_temporary_storage();
    }

    fini(*router);
    shutdown(*server);
}

#import "Basic";
#import,file "../module.jai";