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
    http_server: Http_Server;

    error := init(*http_server, 3000);
    if error then return;

    quit := false;
    while !quit {
        messages, error := http_server_update(*http_server);
        if error then quit = true;

        for messages {
            response := get_response(*it.http_request);
            html(response, "<html>Hello</html>");
            send_response(response);
        }

        reset_temporary_storage();
    }

    shutdown(*http_server);
}

#import "Basic";
#import "Thread";
#import,file "../module.jai";