// Jai doesn't have any async runtime. But we can do something
// async-ish by having an event loop and a state machine. This
// is a very simple example demonstrating this.

main :: () {
    server: Http_Server;

    error := init(*server, 3000);
    if error return;

    queue = initialize_queue(Socket);

    quit := false;
    while !quit {
        peek := clients_to_handle_this_iteration.count > 0;
        peek ||= queue_operations > 0;

        error, events := http_server_update(*server, peek = peek);
        if error quit = true;

        for events {
            if it.type == .Http_Request {
                client := find_or_add(*clients, it.client_socket);
                client.request = it.http_request;
                client.phase = .Sign_In;
                array_add(*clients_to_handle_this_iteration, it.client_socket);
            }
        }

        for clients_to_handle_this_iteration {
            client := table_find_pointer(*clients, it);
            if client == null {
                remove it;
                continue;
            }

            if #complete client.phase == {
                case .Sign_In;
                    // @Todo: Add some authentication.
                    client.phase = .Parse_Request;

                case .Parse_Request;
                    if client.request.uri == "/stop" {
                        quit = true;
                        remove it;
                    } else if starts_with(client.request.uri, "/public") {
                        file := string.{ data = client.request.uri.data + 1, count = client.request.uri.count - 1 };
                        path := join(path_strip_filename(get_path_of_running_executable()), file,, temp);

                        result := read_entire_file(queue, path, it);
                        if result.code != .Success {
                            response := make_response(*client.request,, temp);
                            not_found(*server, response);
                            send_response(*server, response);

                            remove it;
                        }

                        queue_operations += 1;
                        client.phase = .Send_File;

                        // Removing it here is kind of like "await"-ing in some other languages.
                        remove it;
                    } else {
                        response := make_response(*client.request,, temp);
                        html(*server, response, "<html>Hello</html");
                        send_response(*server, response);

                        remove it;
                    }

                case .Send_File;
                    response := make_response(*client.request,, temp);
                    html(*server, response, client.file_data.(string));
                    send_response(*server, response);

                    free(client.file_data.data);
                    table_remove(*clients, it);

                    remove it;
            }
        }

        while queue_operations > 0 {
            socket, data, error := wait_for_completion(queue, check_only = true);
            if error.code != .Success break;

            queue_operations -= 1;

            client := table_find_pointer(*clients, socket);
            if client == null {
                free(*data.data);
                continue;
            }

            client.file_data = data;
            client.phase = .Send_File;

            array_add(*clients_to_handle_this_iteration, socket);
        }

        reset_temporary_storage();
    }

    shutdown(*server);

    report_memory_leaks();
}

Client_Phase :: enum {
    Sign_In;
    Parse_Request;
    Send_File;
}

Client :: struct {
    phase: Client_Phase;

    request: Http_Request;

    file_data: [] u8;
}

clients: Table(Socket, Client);
clients_to_handle_this_iteration: [..] Socket;

queue: *Queue(Socket);
queue_operations: int;

#import "Basic" () (MEMORY_DEBUGGER = true, TEMP_ALLOCATOR_POISON_FREED_MEMORY = true);
#import "File_Async";
#import "Hash_Table";
#import "Socket";
#import "String";
#import "System";
#import,file "../module.jai";