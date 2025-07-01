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

init :: (router: *Http_Router) {
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

get     :: #bake_arguments add_route(method = .GET,     static = false, folder = "");
head    :: #bake_arguments add_route(method = .HEAD,    static = false, folder = "");
post    :: #bake_arguments add_route(method = .POST,    static = false, folder = "");
put     :: #bake_arguments add_route(method = .PUT,     static = false, folder = "");
delete  :: #bake_arguments add_route(method = .DELETE,  static = false, folder = "");
connect :: #bake_arguments add_route(method = .CONNECT, static = false, folder = "");
options :: #bake_arguments add_route(method = .OPTIONS, static = false, folder = "");
trace   :: #bake_arguments add_route(method = .TRACE,   static = false, folder = "");
patch   :: #bake_arguments add_route(method = .PATCH,   static = false, folder = "");

static :: #bake_arguments add_route(method = .GET, handler = null, static = true);

add_route :: (router: *Http_Router, method: Http_Method, path: string, handler: Http_Route_Handler, static: bool, folder: string) -> error: bool {
    ctx := context;
    ctx.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *router.pool };

    push_context ctx {
        if !starts_with(path, "/") return true;

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
            if parts[i] == "" continue;

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

        chip.type = ifx static then .Static else .Dynamic;
        chip.handler = handler;

        if static {
            chip.folder = copy_string(folder);
        }

        return false;
    }
}

http_router_handle_request :: (server: *Http_Server, router: *Http_Router, event: Http_Event) -> handled: bool {
    return http_router_handle_request(server, router, event.http_request);
}

http_router_handle_request :: (server: *Http_Server, router: *Http_Router, request: *Http_Request) -> handled: bool {
    response := make_response(request,, temp);

    if !starts_with(request.uri, "/") return false;

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
        if chip == null return false;
    }

    parts := split(request.uri, "/",, temp);
    offset := 0;

    for parts {
        if it == "" continue;

        path := tprint("/%", it);

        chip = table_find_pointer(chips, path);
        if chip == null {
            chip = table_find_pointer(chips, "/*");
            if chip == null return false;
        }

        chips = chip.children;
        offset += path.count;

        if chip.type == .Static break;
    }

    if #complete chip.type == {
        case .Dynamic;
            if chip.handler == null return false;
            chip.handler(server, request, response);

        case .Static;
            file := string.{ data = request.uri.data + offset, count = request.uri.count - offset };
            error := static_file(server, response, file, join(path_strip_filename(get_path_of_running_executable()), chip.folder,, temp));
            if error return false;
    }

    send_response(server, response);

    return true;
}

#scope_module

Chip_Type :: enum {
    Dynamic;
    Static;
}

Chip :: struct {
    type: Chip_Type;

    handler: Http_Route_Handler;
    children: *Table(string, Chip);

    // Only used when type == .Static
    folder: string;
}
