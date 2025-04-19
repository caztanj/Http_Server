Http_Router :: struct {
    get:     Table(string, Chip);
    head:    Table(string, Chip);
    post:    Table(string, Chip);
    put:     Table(string, Chip);
    delete:  Table(string, Chip);
    connect: Table(string, Chip);
    options: Table(string, Chip);
    trace:   Table(string, Chip);
    patch:   Table(string, Chip);

    pool: Flat_Pool;
    allocator: Allocator;
}

Http_Route_Handler :: #type (request: *Http_Request, response: *Http_Response);

init :: (router: *Http_Router) {
    context.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *router.pool };
    remember_allocators(router);
}

fini :: (router: *Http_Router) {
    fini(*router.pool);
}

get     :: #bake_arguments add_route(method = .GET);
head    :: #bake_arguments add_route(method = .HEAD);
post    :: #bake_arguments add_route(method = .POST);
put     :: #bake_arguments add_route(method = .PUT);
delete  :: #bake_arguments add_route(method = .DELETE);
connect :: #bake_arguments add_route(method = .CONNECT);
options :: #bake_arguments add_route(method = .OPTIONS);
trace   :: #bake_arguments add_route(method = .TRACE);
patch   :: #bake_arguments add_route(method = .PATCH);

add_route :: (router: *Http_Router, method: Http_Method, path: string, handler: Http_Route_Handler) -> error: bool {
    context.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *router.pool };

    if !starts_with(path, "/") then return true;

    chip: *Chip;
    chips: *Table(string, Chip);

    if #complete method == {
        case .GET;      chips = *router.get;
        case .HEAD;     chips = *router.head;
        case .POST;     chips = *router.post;
        case .PUT;      chips = *router.put;
        case .DELETE;   chips = *router.delete;
        case .CONNECT;  chips = *router.connect;
        case .OPTIONS;  chips = *router.options;
        case .TRACE;    chips = *router.trace;
        case .PATCH;    chips = *router.patch;
    }

    parts := split(path, "/",, temp);

    root_path := tprint("/%", parts[1]);

    if table_contains(chips, root_path) {
        chip = table_find_pointer(chips, root_path);
    } else {
        chip = table_add(chips, root_path, .{});
        chip.children = New(Table(string, Chip),, router.allocator);
    }

    chips = chip.children;

    for i: 2..parts.count - 1 {
        if parts[i] == "" then continue;

        path := tprint("/%", parts[i]);

        if table_contains(chips, path) {
            chip = table_find_pointer(chips, path);
        } else {
            chip = table_add(chips, path, .{});
            chip.children = New(Table(string, Chip),, router.allocator);
        }

        chips = chip.children;
    }

    chip.handler = handler;

    return false;
}

http_router_handle_request :: (router: *Http_Router, message: *Message) -> handled: bool {
    response := get_response(*message.http_request);

    if !starts_with(message.http_request.uri, "/") then return false;

    chip: *Chip;
    chips: *Table(string, Chip);

    if #complete message.http_request.method == {
        case .GET;      chips = *router.get;
        case .HEAD;     chips = *router.head;
        case .POST;     chips = *router.post;
        case .PUT;      chips = *router.put;
        case .DELETE;   chips = *router.delete;
        case .CONNECT;  chips = *router.connect;
        case .OPTIONS;  chips = *router.options;
        case .TRACE;    chips = *router.trace;
        case .PATCH;    chips = *router.patch;
    }

    if message.http_request.uri == "/" {
        chip = table_find_pointer(chips, "/");
    }

    parts := split(message.http_request.uri, "/",, temp);

    for parts {
        if it == "" then continue;

        path := tprint("/%", it);

        chip = table_find_pointer(chips, path);
        if chip == null then return false;

        chips = chip.children;
    }

    if chip.handler == null then return false;

    chip.handler(*message.http_request, response);
    send_response(response);

    return true;
}

#scope_module

Chip :: struct {
    handler: Http_Route_Handler;
    children: *Table(string, Chip);
}
