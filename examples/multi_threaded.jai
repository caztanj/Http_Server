main :: () {
    threads: [3] Thread;

    for * threads {
        thread_init(it, worker);
        thread_start(it);
    }

    run_http_server();
}

worker :: (thread: *Thread) -> s64 {
    run_http_server();
    return 0;
}

run_http_server :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error then return;

    quit := false;
    while !quit {
        error, events := http_server_update(*server);
        if error then quit = true;

        for events {
            if it.type != .Http_Request then continue;

            response := make_response(it,, temp);
            html(*server, response, "<html>Hello</html>");
            send_response(*server, response);
        }

        reset_temporary_storage();
    }

    shutdown(*server);
}

#import "Basic";
#import "Thread";
#import,file "../module.jai";