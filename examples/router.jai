main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error return;

    router: Http_Router;
    init(*router);

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

    get(*router, "/hello/*", (server: *Http_Server, request: *Http_Request, response: *Http_Response) {
        html(server, response, "/hello/*");
    });

    get(*router, "/hello/*/abc", (server: *Http_Server, request: *Http_Request, response: *Http_Response) {
        html(server, response, "/hello/*/abc");
    });

    static(*router, "/public", "public");

    quit := false;
    while !quit {
        error, events := http_server_update(*server);
        if error quit = true;

        for events {
            if it.type != .Http_Request continue;

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