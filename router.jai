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

Http_Route_Handler :: #type (server: *Http_Server, request: *Http_Request, response: *Http_Response);

init :: (router: *Http_Router, server: *Http_Server) {
    ctx := context;
    ctx.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *router.pool };

    push_context ctx {
        remember_allocators(router);
        remember_allocators(*router.get);
        remember_allocators(*router.head);
        remember_allocators(*router.post);
        remember_allocators(*router.put);
        remember_allocators(*router.delete);
        remember_allocators(*router.connect);
        remember_allocators(*router.options);
        remember_allocators(*router.trace);
        remember_allocators(*router.patch);
    }
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
    ctx := context;
    ctx.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *router.pool };

    push_context ctx {
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

        root_path := sprint("/%", parts[1]);

        if table_contains(chips, root_path) {
            chip = table_find_pointer(chips, root_path);
        } else {
            chip = table_add(chips, root_path, .{});
            chip.children = New(Table(string, Chip));
            remember_allocators(chip.children);
        }

        chips = chip.children;

        for i: 2..parts.count - 1 {
            if parts[i] == "" then continue;

            path := sprint("/%", parts[i]);

            if table_contains(chips, path) {
                chip = table_find_pointer(chips, path);
            } else {
                chip = table_add(chips, path, .{});
                chip.children = New(Table(string, Chip));
                remember_allocators(chip.children);
            }

            chips = chip.children;
        }

        chip.handler = handler;

        return false;
    }
}

http_router_handle_request :: (server: *Http_Server, router: *Http_Router, request: *Http_Request) -> handled: bool {
    response := make_response(request,, temp);

    if !starts_with(request.uri, "/") then return false;

    chip: *Chip;
    chips: *Table(string, Chip);

    if #complete request.method == {
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

    if request.uri == "/" {
        chip = table_find_pointer(chips, "/");
        if chip == null then return false;
    }

    parts := split(request.uri, "/",, temp);

    for parts {
        if it == "" then continue;

        path := tprint("/%", it);

        chip = table_find_pointer(chips, path);
        if chip == null then return false;

        chips = chip.children;
    }

    if chip.handler == null then return false;

    chip.handler(server, request, response);
    send_response(server, response);

    return true;
}

#scope_module

Chip :: struct {
    handler: Http_Route_Handler;
    children: *Table(string, Chip);
}
