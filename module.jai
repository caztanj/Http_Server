#module_parameters () (MAX_REQUEST_SIZE := 65536);

make_response :: (event: Http_Event) -> *Http_Response {
    return make_response(event.http_request);
}

make_response :: (request: *Http_Request) -> *Http_Response {
    response := New(Http_Response);
    response.client_socket = request.client_socket;
    return response;
}

Http_Event_Type :: enum {
    Http_Request;
    Web_Socket_Message;
    Close;
}

Http_Event :: struct {
    type: Http_Event_Type;

    client_socket: Socket.Socket;

    union {
        http_request: *Http_Request;
        web_socket_message: Web_Socket_Message;
    }
}

Http_Request :: struct {
    allocator: Allocator;
    pool:      Flat_Pool;

    client_socket: Socket.Socket;

    uri:    string;
    method: Http_Method;

    headers: [..] Http_Header;

    body: string;
}

init :: (request: *Http_Request) {
    request.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *request.pool };

    request.headers.allocator = request.allocator;

    request.uri.count = 0;
    request.method    = .GET;

    array_reset(*request.headers);

    request.body.count = 0;
}

reset :: (request: *Http_Request) {
    reset(*request.pool);
    init(request);
}

Http_Response :: struct {
    client_socket: Socket.Socket;

    status: Http_Response_Status;

    headers: [..] Http_Header;
    headers.allocator = temp;

    body: string; // Temporary storage
}

Http_Method :: enum {
    GET;
    HEAD;
    POST;
    PUT;
    DELETE;
    CONNECT;
    OPTIONS;
    TRACE;
    PATCH;
}

Http_Header :: struct {
    key:   string;
    value: string;
}

#insert -> string {
    Http_Response_Status_Spec :: struct {
        key:         string;
        code:        int;
        description: string;
    }

    response_status: [] Http_Response_Status_Spec = .[
        .{ "None", 0, "None" },

        .{ "Continue",            100, "Continue" },
        .{ "Switching_Protocols", 101, "Switching Protocols" },
        .{ "Early_Hints",         103, "Early Hints" },

        .{ "Ok",                            200, "OK" },
        .{ "Created",                       201, "Created" },
        .{ "Accepted",                      202, "Accepted" },
        .{ "Non_Authoritative_Information", 203, "Non Authoritative Information" },
        .{ "No_Content",                    204, "No Content" },
        .{ "Reset_Content",                 205, "Reset Content" },
        .{ "Partial_Content",               206, "Partial Content" },

        .{ "Multiple_Choices",   300, "Multiple Choices" },
        .{ "Moved_Permanently",  301, "Moved Permanently" },
        .{ "Found",              302, "Found" },
        .{ "See_Other",          303, "See Other" },
        .{ "Not_Modified",       304, "Not Modified" },
        .{ "Temporary_Redirect", 307, "Temporary Redirect" },
        .{ "Permanent_Redirect", 308, "Permanent Redirect" },

        .{ "Bad_Request",                     400, "Bad Request" },
        .{ "Unauthorized",                    401, "Unauthorized" },
        .{ "Payment_Required",                402, "Payment Required" },
        .{ "Forbidden",                       403, "Forbidden" },
        .{ "Not_Found",                       404, "Not Found" },
        .{ "Method_Not_Allowed",              405, "Method Not Allowed" },
        .{ "Not_Acceptable",                  406, "Not Acceptable" },
        .{ "Proxy_Authentication_Required",   407, "Proxy Authentication Required" },
        .{ "Request_Timeout",                 408, "Request Timeout" },
        .{ "Conflict",                        409, "Conflict" },
        .{ "Gone",                            410, "Gone" },
        .{ "Length_Required",                 411, "Length Required" },
        .{ "Precondition_Failed",             412, "Precondition Failed" },
        .{ "Content_Too_Large",               413, "Content Too Large" },
        .{ "Uri_Too_Long",                    414, "URI Too Long" },
        .{ "Unsupported_Media_Type",          415, "Unsupported Media Type" },
        .{ "Range_Not_Satisfiable",           416, "Range Not Satisfiable" },
        .{ "Expectation_Failed",              417, "Expectation Failed" },
        .{ "I_Am_A_Teapot",                   418, "I'm not a teapot" },
        .{ "Misdirected_Request",             421, "Misdirected Request" },
        .{ "Upgrade_Required",                426, "Upgrade Required" },
        .{ "Precondition_Required",           428, "Precondition Required" },
        .{ "Too_Many_Requests",               429, "Too Many Requests" },
        .{ "Request_Header_Fields_Too_Large", 431, "Request Header Fields Too Large" },
        .{ "Unavailable_For_Legal_Reasons",   451, "Unavailable For Legal Reasons" },

        .{ "Internal_Server_Error",           500, "Internal Server Error" },
        .{ "Not_Implemented",                 501, "Not Implemented" },
        .{ "Bad_Gateway",                     502, "Bad Gateway" },
        .{ "Service_Unavailable",             503, "Service Unavailable" },
        .{ "Gateway_Timeout",                 504, "Gateway Timeout" },
        .{ "Http_Version_Not_Supported",      505, "HTTP Version Not Supported" },
        .{ "Variant_Also_Negotiates",         506, "Variant Also Negotiates" },
        .{ "Not_Extended",                    510, "Not Extended" },
        .{ "Network_Authentication_Required", 511, "Network Authentication Required" },
    ];

    b: String_Builder;

    append(*b, "Http_Response_Status :: enum {\n");

    for response_status {
        append(*b, sprint("    % :: %;\n", it.key, it.code));
    }

    append(*b, "}\n");

    append(*b, "\n");

    append(*b, "response_status_to_string :: (status: Http_Response_Status) -> string {\n");
    append(*b, "    if #complete status == {\n");

    for response_status {
        append(*b, sprint("        case .%;  return \"% %\";\n", it.key, it.code, it.description));
    }

    append(*b, "    }\n");
    append(*b, "}\n");

    return builder_to_string(*b);
}

set_header :: (headers: *[..] Http_Header, key: string, value: string) {
    for * headers.* {
        if equal_nocase(it.key, key) {
            it.value = value;
            return;
        }
    }

    header := Http_Header.{ key = key, value = value };
    array_add(headers, header);
}

get_header :: (headers: [] Http_Header, key: string) -> error: bool, string {
    for headers {
        if equal_nocase(it.key, key) return false, it.value;
    }

    return true, "";
}

static_file :: (server: *Http_Server, response: *Http_Response, file: string, directory: string) -> error: bool {
    path := join(directory, "/", file,, temp);

    if contains(path, "..") return true;

    content, success := read_entire_file(path,, temp);
    if !success {
        path = join(path, "/index.html",, temp);
        content, success = read_entire_file(path,, temp);
        if !success return true;
    }

    if ends_with(path, ".html") {
        return html(server, response, content);
    } else if ends_with(path, ".css") {
        return css(server, response, content);
    } else if ends_with(path, ".js") {
        return js(server, response, content);
    } else if ends_with(path, ".json") {
        return json(server, response, content);
    } else {
        return text(server, response, content);
    }

    return false;
}

text :: (server: *Http_Server, response: *Http_Response, text: string) -> error: bool {
    return text_response(server, response, text, "text/plain");
}

html :: (server: *Http_Server, response: *Http_Response, html: string) -> error: bool {
    return text_response(server, response, html, "text/html");
}

css :: (server: *Http_Server, response: *Http_Response, css: string) -> error: bool {
    return text_response(server, response, css, "text/css");
}

js :: (server: *Http_Server, response: *Http_Response, js: string) -> error: bool {
    return text_response(server, response, js, "application/js");
}

json :: (server: *Http_Server, response: *Http_Response, json: string) -> error: bool {
    return text_response(server, response, json, "application/json");
}

not_found :: (server: *Http_Server, response: *Http_Response) -> error: bool {
    client := find_client(server, response.client_socket);
    if client == null return true;

    response.status = .Not_Found;

    set_header(*response.headers, "Content-Length", "0");

    if client.close_after_send {
        set_header(*response.headers, "Connection", "close");
    } else {
        set_header(*response.headers, "Connection", "keep-alive");
        set_header(*response.headers, "Keep-Alive", "timeout=30");
    }

    return false;
}

bad_request :: (server: *Http_Server, response: *Http_Response) -> error: bool {
    client := find_client(server, response.client_socket);
    if client == null return true;

    response.status = .Bad_Request;

    if client.close_after_send {
        set_header(*response.headers, "Connection", "close");
    } else {
        set_header(*response.headers, "Connection", "keep-alive");
        set_header(*response.headers, "Keep-Alive", "timeout=30");
    }

    return false;
}

internal_server_error :: (server: *Http_Server, response: *Http_Response) -> error: bool {
    client := find_client(server, response.client_socket);
    if client == null return true;

    response.status = .Internal_Server_Error;

    if client.close_after_send {
        set_header(*response.headers, "Connection", "close");
    } else {
        set_header(*response.headers, "Connection", "keep-alive");
        set_header(*response.headers, "Keep-Alive", "timeout=30");
    }

    return false;
}

decode_uri :: (uri: string) -> error: bool, string {
    b: String_Builder;
    b.allocator = temp;

    t     := uri.data;
    max_t := t + uri.count;

    current := string.{ count = 2 };

    while t < max_t {
        if t.* == "%" {
            t += 2;
            if t >= max_t return true, "";

            current.data = t - 1;
            if !is_digits(current) return true, "";

            result, success := string_to_int(current, 16, u8);
            if !success return true, "";

            append(*b, *result, 1);
        } else {
            append(*b, t, 1);
        }

        t += 1;
    }

    return false, builder_to_string(*b);
}

print_http_request :: (request: *Http_Request) {
    b: String_Builder;
    b.allocator = temp;

    if #complete request.method == {
        case .GET;      append(*b, "GET");
        case .HEAD;     append(*b, "HEAD");
        case .POST;     append(*b, "POST");
        case .PUT;      append(*b, "PUT");
        case .DELETE;   append(*b, "DELETE");
        case .CONNECT;  append(*b, "CONNECT");
        case .OPTIONS;  append(*b, "OPTIONS");
        case .TRACE;    append(*b, "TRACE");
        case .PATCH;    append(*b, "PATCH");
    }

    append(*b, " ");
    append(*b, request.uri);
    append(*b, " ");
    append(*b, "HTTP/1.1");
    append(*b, "\n");

    for request.headers {
        append(*b, it.key);
        append(*b, ": ");
        append(*b, it.value);
        append(*b, "\n");
    }

    if request.body.count > 0 {
        append(*b, "\n");
        append(*b, request.body);
    }

    s := builder_to_string(*b,, temp);

    print("%", s);
}

#scope_module

text_response :: (server: *Http_Server, response: *Http_Response, text: string, content_type: string) -> error: bool {
    client := find_client(server, response.client_socket);
    if client == null return true;

    response.status = .Ok;
    response.body   = text;

    set_header(*response.headers, "Content-Type", content_type);
    set_header(*response.headers, "Content-Length", tprint("%", text.count));

    if client.close_after_send {
        set_header(*response.headers, "Connection", "close");
    } else {
        set_header(*response.headers, "Connection", "keep-alive");
        set_header(*response.headers, "Keep-Alive", "timeout=30");
    }

    return false;
}

is_digits :: (s: string) -> bool {
    t     := s.data;
    max_t := t + s.count;

    while t < max_t {
        if t.* < "0" || t.* > "9" return false;
        t += 1;
    }

    return true;
}

Parse_Request_Status :: enum {
    Error;
    Need_More_Data;
    Success;
}

parse_request :: (client: *Http_Client) -> Parse_Request_Status {
    client.t     = client.buffer.data;
    client.max_t = client.t + client.buffer_count;

    status := parse_request_line(client);
    if status != .Success return status;

    content_length := 0;

    while true {
        if client.t.* == "\r" {
            client.t += 1;
            if client.t >= client.max_t return .Need_More_Data;
            if client.t.* != "\n"         return .Error;
            client.t += 1;
            break;
        }

        status, header := parse_header(client);
        if status != .Success return status;

        if equal_nocase(header.key, "Content-Length") {
            result, success := string_to_int(header.value);
            if !success return .Error;
            content_length = result;
        }

        array_add(*client.request.headers, header);
    }

    if content_length {
        if client.t + content_length > client.max_t return .Need_More_Data;

        client.request.body = copy_string(string.{ data = client.t, count = content_length },, client.request.allocator);

        client.t += content_length + 1;
    }

    return .Success;
}

parse_request_line :: (using client: *Http_Client) -> Parse_Request_Status {
    m := string.{ data = t };

    while t < max_t {
        if t - m.data > 7      return .Error;
        if t.* == " "    break;
        if t.* == "\r"   return .Error;
        t += 1;
    }

    if t >= max_t return .Need_More_Data;

    m.count = t - m.data;

    if m == {
        case "GET";      request.method = .GET;
        case "HEAD";     request.method = .HEAD;
        case "POST";     request.method = .POST;
        case "PUT";      request.method = .PUT;
        case "DELETE";   request.method = .DELETE;
        case "CONNECT";  request.method = .CONNECT;
        case "OPTIONS";  request.method = .OPTIONS;
        case "TRACE";    request.method = .TRACE;
        case "PATCH";    request.method = .PATCH;

        case;  return .Error;
    }

    t += 1;
    if t >= max_t return .Need_More_Data;

    uri := string.{ data = t };

    while t < max_t {
        if t.* == " "  break;
        if t.* == "\r" return .Error;
        t += 1;
    }

    if t >= max_t return .Need_More_Data;

    uri.count = t - uri.data;

    request.uri = copy_string(uri,, client.request.allocator);

    t += 1;
    if t >= max_t return .Need_More_Data;

    version := string.{ data = t };

    while t < max_t {
        if t - version.data > 8 return .Error;

        if t.* == "\r" {
            t += 1;
            if t >= max_t        return .Need_More_Data;
            if t.* != "\n" return .Error;
            break;
        }

        version.count += 1;
        t += 1;
    }

    if version != "HTTP/1.1" return .Error;

    t += 1;
    if t >= max_t return .Need_More_Data;

    return .Success;
}

parse_header :: (using client: *Http_Client) -> Parse_Request_Status, Http_Header {
    key := string.{ data = t };

    while t < max_t {
        if t.* == ":" break;
        t += 1;
    }

    if t >= max_t return .Need_More_Data, .{};

    key.count = t - key.data;

    key = trim(key, chars=" ");

    t += 1;
    if t >= max_t return .Need_More_Data, .{};

    value := string.{ data = t };

    while t < max_t {
        if t.* == "\r" {
            t += 1;
            if t >= max_t        return .Need_More_Data, .{};
            if t.* != "\n" return .Error, .{};
            break;
        }

        value.count += 1;
        t += 1;
    }

    t += 1;
    if t >= max_t return .Need_More_Data, .{};

    value = trim(value, chars=" ");

    return .Success, .{ key = key, value = value };
}

Chunk :: struct {
    buffer:        [4096] u8;
    bytes_to_send: int;
    bytes_sent:    int;
}

Http_Client_Protocol :: enum {
    Http;
    Upgrading_To_Web_Socket; // This is not really a protocol. It is more of an in-between state between Http and Web_Socket.
    Web_Socket;
}

Http_Client :: struct {
    socket: Socket.Socket;
    protocol: Http_Client_Protocol;

    ssl: *LibreSSL.SSL;

    chunks_to_send: [..] Chunk;

    timeout: Apollo_Time;

    close_after_send: bool;

    request: Http_Request;

    buffer: [..] u8;
    buffer_count: int;

    t:     *u8;
    max_t: *u8;

    // These are only used by web sockets.
    waiting_for_fin_frame: bool;
    buffer_offset:         int;
}

init :: (client: *Http_Client, socket: Socket.Socket) {
    client.request.client_socket = socket;
    init(*client.request);
}

add_client :: (server: *Http_Server, socket: Socket.Socket) -> *Http_Client {
    client := New(Http_Client);

    init(client, socket);

    client.socket = socket;

    set_timeout(client, 5);

    table_add(*server.clients, socket, client);

    return client;
}

find_client :: (server: *Http_Server, socket: Socket.Socket) -> *Http_Client {
    success, client := table_find_new(*server.clients, socket);
    if !success return null;
    return client;
}

remove_client :: (server: *Http_Server, client: *Http_Client) {
    table_remove(*server.clients, client.socket);

    array_reset(*client.buffer);

    array_reset(*client.request.headers);
    array_reset(*client.chunks_to_send);

    free(client);
}

set_timeout :: (client: *Http_Client, timeout: int) {
    client.timeout = current_time_monotonic() + seconds_to_apollo(timeout);
}

add_web_socket_event :: (events: *[..] Http_Event, socket: Socket.Socket, type: Web_Socket_Message_Type) -> *Http_Event {
    event := array_add(events);

    event.type = .Web_Socket_Message;
    event.client_socket = socket;
    event.web_socket_message.type = type;
    event.web_socket_message.client_socket = socket;

    return event;
}

add_web_socket_event :: (events: *[..] Http_Event, socket: Socket.Socket, type: Web_Socket_Message_Type, frame: Web_Socket_Frame) -> *Http_Event {
    event := add_web_socket_event(events, socket, type);

    event.web_socket_message.frame = frame;

    return event;
}

maybe_parse_request_or_web_socket_message :: (server: *Http_Server, socket: Socket.Socket, events: *[..] Http_Event) -> again: bool {
    client := find_client(server, socket);
    assert(client != null);

    if client.protocol == {
        case .Http;
            again := maybe_parse_http_request(server, client, events);
            return again;

        case .Upgrading_To_Web_Socket;
            assert(false, "unreachable");

        case .Web_Socket;
            again := maybe_parse_web_socket_message(server, client, events);
            return again;
    }

    return false;
}

maybe_parse_http_request :: (server: *Http_Server, client: *Http_Client, events: *[..] Http_Event) -> again: bool {
    status := parse_request(client);
    if #complete status == {
        case .Error;
            close(server, client);
            return false;

        case .Need_More_Data;
            return false;

        case .Success;
            event := array_add(events);
            event.type = .Http_Request;
            event.client_socket = client.socket;
            event.http_request = *client.request;
            return false;
    }
}

maybe_parse_web_socket_message :: (server: *Http_Server, client: *Http_Client, events: *[..] Http_Event) -> again: bool {
    if !client.waiting_for_fin_frame {
        client.t = client.buffer.data;
    } else {
        client.t = client.buffer.data + client.buffer_offset;
    }

    client.max_t = client.buffer.data + client.buffer_count;

    t     := client.t;
    max_t := client.max_t;

    again := false;

    status, frame := parse_web_socket_frame(client,, temp);
    if status == .Need_More_Data {
        client.t = t;
        client.max_t = max_t;
        return false;
    }

    if status == .Error {
        close(server, client);
        return false;
    }

    if frame.rsv1 || frame.rsv2 || frame.rsv3 {
        add_web_socket_event(events, client.socket, .Error);
        return false;
    }

    if !frame.fin {
        if frame.opcode == .Control_Frame_Ping || frame.opcode == .Control_Frame_Pong {
            close(server, client);
            return false;
        }

        if !client.waiting_for_fin_frame && frame.opcode == .Continuation {
            add_web_socket_event(events, client.socket, .Error);
            return false;
        }

        client.waiting_for_fin_frame = true;
        client.buffer_offset = client.t - client.buffer.data;

        return true;
    }

    if frame.fin && client.waiting_for_fin_frame && frame.opcode == .Continuation {
        client.t     = client.buffer.data;
        client.max_t = client.buffer.data + client.buffer_count;

        status, frame = merge_continuation_frames(client,, temp);
        if status != .Success {
            close(server, client);
            return false;
        }

        client.waiting_for_fin_frame = false;
        t = client.buffer.data;
    }

    if client.t < client.max_t {
        again = true;
    }

    count := client.max_t - client.t;
    memcpy(t, client.t, count);

    if client.waiting_for_fin_frame {
        client.buffer_count = t - client.buffer.data + count;
    } else {
        client.buffer_count = count;
    }

    if #complete frame.opcode == {
        case .Continuation;
            if !client.waiting_for_fin_frame {
                close(server, client);
                return false;
            }

        case .Control_Frame_Close;
            event := array_add(events);
            event.type = .Close;
            event.client_socket = client.socket;

            send_web_socket_close_frame(server, client);

        case .Control_Frame_Pong;

        case .Control_Frame_Ping;
            add_web_socket_event(events, client.socket, .Ping, frame);

        case .Data_Frame_Text;
            if client.waiting_for_fin_frame {
                close(server, client);
                return false;
            }

            // @Todo: Autobahn 6.4.* are Non-Strict
            if !is_valid_utf8(frame.payload) {
                close(server, client);
                return false;
            }

            add_web_socket_event(events, client.socket, .Text, frame);

        case .Data_Frame_Binary;
            if client.waiting_for_fin_frame {
                close(server, client);
                return false;
            }

            add_web_socket_event(events, client.socket, .Binary, frame);

        case;
            add_web_socket_event(events, client.socket, .Error);

    }

    return again;
}

MIN_BUFFER_SIZE :: 65536;

#import "Base64";
#import "Basic";
#import "File";
#import "File_Utilities";
#import "Flat_Pool";
#import "Hash_Table";
#import "String";
#import "System";

Socket :: #import "Socket";

#load "poll.jai";
#load "router.jai";
#load "tests/tests.jai";
#load "utf8.jai";
#load "websocket.jai";

create_context :: () -> *LibreSSL.SSL_CTX {
    method := LibreSSL.TLS_server_method();
    ctx := LibreSSL.SSL_CTX_new(method);
    if !ctx {
        print_ssl_errors();
        return null;
    }

    return ctx;
}

configure_context :: (ctx: *LibreSSL.SSL_CTX, certificate_file: string, private_key_file: string) -> error: bool {
    if LibreSSL.SSL_CTX_use_certificate_file(ctx, temp_c_string(certificate_file), LibreSSL.SSL_FILETYPE_PEM) <= 0 {
        print_ssl_errors();
        return true;
    }

    if LibreSSL.SSL_CTX_use_PrivateKey_file(ctx, temp_c_string(private_key_file), LibreSSL.SSL_FILETYPE_PEM) <= 0 {
        print_ssl_errors();
        return true;
    }

    return false;
}

print_ssl_errors :: () {
    #if OS == .WINDOWS {
        buffer: [1024] u8;
        bio := LibreSSL.BIO_new(LibreSSL.BIO_s_mem());
        LibreSSL.ERR_print_errors(bio);

        s: string = ---;
        s.data = buffer.data;

        count := LibreSSL.BIO_read(bio, buffer.data, buffer.count);

        if count > 0 {
            s.count = count;
            print("%\n", s);
        }

        LibreSSL.BIO_free(bio);
    } else {
        LibreSSL.ERR_print_errors_fp(POSIX.stderr);
    }
}

LibreSSL :: #import,dir "modules/LibreSSL";

#if OS == .LINUX {
    #load "linux.jai";

    Linux :: #import "Linux";
    POSIX :: #import "POSIX";
}

#if OS == .WINDOWS {
    #load "windows.jai";

    Windows :: #import "Windows";
}

#if OS == .MACOS {
    #load "macos.jai";

    Macos :: #import "macos";
    POSIX :: #import "POSIX";
}