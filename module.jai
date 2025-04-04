#module_parameters () (ENABLE_TLS := false);

get_response :: (request: *Http_Request) -> *Http_Response {
    return *request.client.response;
}

Http_Request :: struct {
    uri:    string;
    method: Http_Method;

    headers: [..] Http_Header;

    body: string;

    raw:       [MAX_REQUEST_SIZE] u8;
    raw_count: int;

    client: *Http_Client;
}

Http_Response :: struct {
    status: Http_Response_Status;

    headers: [..] Http_Header;

    body: string;

    // @Todo: Make this a [] u8 so we can send binary data.
    serialized: string;
    bytes_sent: int;

    client: *Http_Client;
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
        key:    string;
        code:        int;
        description: string;
    }

    response_status : [] Http_Response_Status_Spec = .[
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

get_header :: (headers: [] Http_Header, key: string) -> string, error: bool #must {
    for headers {
        if equal_nocase(it.key, key) then return it.value, false;
    }

    return "", true;
}

html :: (response: *Http_Response, html: string) {
    response.status = .Ok;
    response.body   = html;

    set_header(*response.headers, "Content-Type", "text/html");
}

not_found :: (response: *Http_Response) {
    response.status = .Not_Found;
}

bad_request :: (response: *Http_Response) {
    response.status = .Bad_Request;
}

#scope_module

Parse_Request_Status :: enum {
    Error;
    Need_More_Data;
    Success;
}

parse_request :: (client: *Http_Client) -> Parse_Request_Status {
    s := string.{ data = client.request.raw.data, count = client.request.raw_count };

    method, found := parse_token(*s, delimiters=" \r", spaces="");
    if !found then return .Need_More_Data;

    if method == {
        case "GET";      client.request.method = .GET;
        case "HEAD";     client.request.method = .HEAD;
        case "POST";     client.request.method = .POST;
        case "PUT";      client.request.method = .PUT;
        case "DELETE";   client.request.method = .DELETE;
        case "CONNECT";  client.request.method = .CONNECT;
        case "OPTIONS";  client.request.method = .OPTIONS;
        case "TRACE";    client.request.method = .TRACE;
        case "PATCH";    client.request.method = .PATCH;

        case;
            if method.count > 7 || starts_with(s, " ") then return .Error;
            return .Need_More_Data;
    }

    s = trim_left(s, chars=" ");

    uri:, found = parse_token(*s, delimiters=" \r", spaces="");
    if !found then return .Need_More_Data;

    client.request.uri = uri;

    s = trim_left(s, chars=" ");

    version:, found = parse_token(*s, delimiters="\r", spaces="");
    if !found then return .Need_More_Data;

    if version != "HTTP/1.1" then return .Error;

    if s.count < 2 then return .Need_More_Data;
    if !starts_with(s, "\r\n") then return .Error;

    advance(*s, 2);

    // No headers and no body.
    if starts_with(s, "\r\n") then return .Success;

    content_length := 0;

    while true {
        s = trim_left(s, chars=" ");

        key, found := parse_token(*s, delimiters=":", spaces="");
        if !found then return .Need_More_Data;

        if s.count == 0 then return .Need_More_Data;

        advance(*s);

        s = trim_left(s, chars=" ");

        value:, found = parse_token(*s, delimiters="\r", spaces="");
        if !found then return .Need_More_Data;

        if s.count < 2 then return .Need_More_Data;
        if !starts_with(s, "\r\n") then return .Error;

        advance(*s, 2);

        if equal_nocase(key, "Content-Length") {
            result, success := string_to_int(value);
            if !success then return .Error;

            content_length = result;
        }

        header := Http_Header.{ key = key, value = value };
        array_add(*client.request.headers, header);

        if starts_with(s, "\r\n") {
            advance(*s, 2);
            break;
        }
    }

    if content_length {
        client.request.body = s;
        client.request.body.count = content_length;
    }

    return .Success;
}

reset :: (client: *Http_Client) {
    reset(*client.pool);

    array_reset_keeping_memory(*client.request.headers);
    array_reset_keeping_memory(*client.response.headers);

    client.request.uri.count  = 0;
    client.request.method     = .GET;
    client.request.body.count = 0;
    client.request.raw_count  = 0;

    client.response.status           = .None;
    client.response.body.count       = 0;
    client.response.serialized.count = 0;
    client.response.bytes_sent       = 0;
}

Http_Client :: struct {
    socket: Socket.Socket;
    server: *Http_Server;

    #if ENABLE_TLS {
        ssl:    *SSL;
    }

    request:  Http_Request;
    response: Http_Response;

    timeout: Apollo_Time;

    close_after_send: bool;

    handed_off_to_main_loop: bool;
    close: bool;

    pool:      Flat_Pool;
    allocator: Allocator;

    locator: Bucket_Locator;
}

init :: (server: *Http_Server, client: *Http_Client) {
    context.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *client.pool };

    remember_allocators(client);
    remember_allocators(*client.request.headers);
    remember_allocators(*client.response.headers);

    // @Todo: Do we need this on both request and response?
    client.request.client = client;
    client.response.client = client;

    client.server = server;
}

fini :: (client: *Http_Client) {
    fini(*client.pool);
}

add_client :: (server: *Http_Server, socket: Socket.Socket) -> *Http_Client {
    client, locator := find_and_occupy_empty_slot(*server.clients);

    init(server, client);

    client.socket = socket;
    client.locator = locator;

    set_timeout(client, 5);

    return client;
}

find_client :: (server: *Http_Server, socket: Socket.Socket) -> *Http_Client {
    for * server.clients {
        if it.socket == socket then return it;
    }

    return null;
}

remove_client :: (client: *Http_Client) {
    bucket_array_remove(*client.server.clients, client.locator);
}

set_timeout :: (client: *Http_Client, timeout: int) {
    client.timeout = current_time_monotonic() + seconds_to_apollo(timeout);
}

MAX_REQUEST_SIZE :: 65536;

#import "Basic";
#import "Bucket_Array";
#import "Flat_Pool";
#import "String";

Socket :: #import "Socket";

#load "tests.jai";

#if ENABLE_TLS {
    #load "openssl.jai";
}

#if OS == .LINUX {
    #load "linux.jai";

    Linux  :: #import "Linux";
    POSIX  :: #import "POSIX";
}
