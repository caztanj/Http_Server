main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error return;

    quit := false;
    while !quit {
        error, events := http_server_update(*server);
        if error quit = true;

        for events {
            if it.type != .Http_Request continue;

            response := make_response(it,, temp);

            html(*server, response, "<html>Hello</html>");
            send_response(*server, response);
        }

        reset_temporary_storage();
    }

    shutdown(*server);

    report_memory_leaks();
}

#import "Basic" () (MEMORY_DEBUGGER = true, TEMP_ALLOCATOR_POISON_FREED_MEMORY = true);
#import,file "../module.jai";