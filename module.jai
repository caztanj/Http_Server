#module_parameters () (ENABLE_TLS := false);

make_response :: (request: *Http_Request) -> *Http_Response {
    response := New(Http_Response);
    response.client_id = request.client_id;
    return response;
}

Http_Request :: struct {
    client_id: Socket.Socket;

    uri:    string;
    method: Http_Method;

    headers: [..] Http_Header;

    body: string; // View into raw

    raw:       [MAX_REQUEST_SIZE] u8;
    raw_count: int;

    t:     *u8;
    max_t: *u8;
}

Http_Response :: struct {
    client_id: Socket.Socket;

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

html :: (server: *Http_Server, response: *Http_Response, html: string) -> error: bool {
    client := find_client(server, response.client_id);
    if client == null then return true;

    response.status = .Ok;
    response.body   = html;

    set_header(*response.headers, "Content-Type", "text/html");
    set_header(*response.headers, "Content-Length", tprint("%", html.count));

    if client.close_after_send {
        set_header(*response.headers, "Connection", "close");
    } else {
        set_header(*response.headers, "Connection", "keep-alive");
        set_header(*response.headers, "Keep-Alive", "timeout=30");
    }

    return false;
}

not_found :: (server: *Http_Server, response: *Http_Response) -> error: bool {
    client := find_client(server, response.client_id);
    if client == null then return true;

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
    client := find_client(server, response.client_id);
    if client == null then return true;

    response.status = .Bad_Request;

    if client.close_after_send {
        set_header(*response.headers, "Connection", "close");
    } else {
        set_header(*response.headers, "Connection", "keep-alive");
        set_header(*response.headers, "Keep-Alive", "timeout=30");
    }

    return false;
}

decode_uri :: (uri: string) -> string, error: bool #must {
    b: String_Builder;
    b.allocator = temp;

    t     := uri.data;
    max_t := t + uri.count;

    current := string.{ count = 2 };

    while t < max_t {
        if t.* == #char "%" {
            t += 2;
            if t >= max_t then return "", true;

            current.data = t - 1;
            if !is_digits(current) then return "", true;

            result, success := string_to_int(current, 16, u8);
            if !success then return "", true;

            append(*b, *result, 1);
        } else {
            append(*b, t, 1);
        }

        t += 1;
    }

    return builder_to_string(*b), false;
}

#scope_module

is_digits :: (s: string) -> bool {
    t     := s.data;
    max_t := t + s.count;

    while t < max_t {
        if t.* < #char "0" || t.* > #char "9" then return false;
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
    client.request.t     = client.request.raw.data;
    client.request.max_t = client.request.t + client.request.raw_count;

    status := parse_request_line(*client.request);
    if status != .Success then return status;

    content_length := 0;

    while true {
        if client.request.t.* == #char "\r" {
            client.request.t += 1;
            if client.request.t >= client.request.max_t then return .Need_More_Data;
            if client.request.t.* != #char "\n"         then return .Error;
            client.request.t += 1;
            break;
        }

        status, header := parse_header(*client.request);
        if status != .Success then return status;

        if equal_nocase(header.key, "Content-Length") {
            result, success := string_to_int(header.value);
            if !success then return .Error;
            content_length = result;
        }

        array_add(*client.request.headers, header);
    }

    if content_length {
        if client.request.t + content_length > client.request.max_t then return .Need_More_Data;

        client.request.body.data = client.request.t;
        client.request.body.count = content_length;

        client.request.t += content_length + 1;
    }

    return .Success;
}

parse_request_line :: (using request: *Http_Request) -> Parse_Request_Status {
    m := string.{ data = t };

    while t < max_t {
        if t - m.data > 7      then return .Error;
        if t.* == #char " "    then break;
        if t.* == #char "\r"   then return .Error;
        t += 1;
    }

    if t >= max_t then return .Need_More_Data;

    m.count = t - m.data;

    if m == {
        case "GET";      method = .GET;
        case "HEAD";     method = .HEAD;
        case "POST";     method = .POST;
        case "PUT";      method = .PUT;
        case "DELETE";   method = .DELETE;
        case "CONNECT";  method = .CONNECT;
        case "OPTIONS";  method = .OPTIONS;
        case "TRACE";    method = .TRACE;
        case "PATCH";    method = .PATCH;

        case;  return .Error;
    }

    t += 1;
    if t >= max_t then return .Need_More_Data;

    uri.data = t;

    while t < max_t {
        if t.* == #char " "  then break;
        if t.* == #char "\r" then return .Error;
        t += 1;
    }

    if t >= max_t then return .Need_More_Data;

    uri.count = t - uri.data;

    t += 1;
    if t >= max_t then return .Need_More_Data;

    version := string.{ data = t };

    while t < max_t {
        if t - version.data > 8 then return .Error;

        if t.* == #char "\r" {
            t += 1;
            if t >= max_t        then return .Need_More_Data;
            if t.* != #char "\n" then return .Error;
            break;
        }

        version.count += 1;
        t += 1;
    }

    if version != "HTTP/1.1" then return .Error;

    t += 1;
    if t >= max_t then return .Need_More_Data;

    return .Success;
}

parse_header :: (using request: *Http_Request) -> Parse_Request_Status, Http_Header {
    key := string.{ data = t };

    while t < max_t {
        if t.* == #char ":" then break;
        t += 1;
    }

    if t >= max_t then return .Need_More_Data, .{};

    key.count = t - key.data;

    key = trim(key, chars=" ");

    t += 1;
    if t >= max_t then return .Need_More_Data, .{};

    value := string.{ data = t };

    while t < max_t {
        if t.* == #char "\r" {
            t += 1;
            if t >= max_t        then return .Need_More_Data, .{};
            if t.* != #char "\n" then return .Error, .{};
            break;
        }

        value.count += 1;
        t += 1;
    }

    t += 1;
    if t >= max_t then return .Need_More_Data, .{};

    value = trim(value, chars=" ");

    return .Success, .{ key = key, value = value };
}

Chunk :: struct {
    buffer:        [4096] u8;
    bytes_to_send: int;
    bytes_sent:    int;
}

Http_Client_Phase :: enum {
    Http;
    Upgrading_To_Web_Socket;
    Web_Socket;
}

Http_Client :: struct {
    socket: Socket.Socket;
    phase: Http_Client_Phase;

    #if ENABLE_TLS {
        ssl: *LibreSSL.SSL;
    }

    request: Http_Request;

    chunks_to_send: [..] Chunk;

    timeout: Apollo_Time;

    close_after_send: bool;
}

init :: (client: *Http_Client, socket: Socket.Socket) {
    client.request.client_id = socket;
}

add_client :: (server: *Http_Server, socket: Socket.Socket) -> *Http_Client {
    client := New(Http_Client);

    init(client, socket);

    client.socket = socket;

    set_timeout(client, 5);

    table_add(*server.clients, socket, client);

    return client;
}

find_client :: (server: *Http_Server, id: Socket.Socket) -> *Http_Client {
    client, success := table_find(*server.clients, id);
    if !success then return null;
    return client;
}

remove_client :: (server: *Http_Server, client: *Http_Client) {
    table_remove(*server.clients, client.socket);
    array_reset(*client.request.headers);
    array_reset(*client.chunks_to_send);
    free(client);
}

set_timeout :: (client: *Http_Client, timeout: int) {
    client.timeout = current_time_monotonic() + seconds_to_apollo(timeout);
}

maybe_parse_request_or_web_socket_message :: (server: *Http_Server, socket: Socket.Socket, requests: *[..] *Http_Request, web_socket_events: *[..] Web_Socket_Event) {
    client := find_client(server, socket);
    if client != null {
        if client.phase == .Web_Socket {
            frame, error := parse_web_socket_frame(client,, temp);
            if error {
                // @Todo: .Need_More_Data?
                // close(server, client);
                return;
            }

            web_socket_event := array_add(web_socket_events);
            web_socket_event.client_id = client.socket;
            web_socket_event.frame = *frame;
        } else {
            status := parse_request(client);
            if #complete status == {
                case .Error;
                    close(server, client);
                    return;

                case .Need_More_Data;
                    return;

                case .Success;
                    array_add(requests, *client.request);
            }
        }
    }
}

MAX_REQUEST_SIZE :: 65536;

#import "Base64";
#import "Basic";
#import "File_Utilities";
#import "Flat_Pool";
#import "Hash_Table";
#import "String";
#import "System";

Socket :: #import "Socket";

#load "poll.jai";
#load "router.jai";
#load "tests.jai";
#load "websocket.jai";

#if ENABLE_TLS {
    create_context :: () -> *LibreSSL.SSL_CTX {
        method := LibreSSL.TLS_server_method();
        ctx := LibreSSL.SSL_CTX_new(method);
        if !ctx {
            print_ssl_errors();
            return null;
        }

        return ctx;
    }

    configure_context :: (ctx: *LibreSSL.SSL_CTX, certificate_file: string, private_key_file: string) -> error: bool #must {
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
}

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