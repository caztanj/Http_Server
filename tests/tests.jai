#run {
    prepare_client :: (request: string) -> Http_Client {
        client: Http_Client;
        client.request.raw = NewArray(65535, u8);
        memcpy(client.request.raw.data, request.data, request.count);
        client.request.raw_count = request.count;
        return client;
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .GET);
        assert(client.request.uri == "/");
        assert(client.request.headers.count == 0);
        assert(client.request.body.count == 0);
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .GET);
        assert(client.request.uri == "/");
        assert(client.request.body.count == 0);

        error, header_value := get_header(client.request.headers, "Host");
        assert(!error);
        assert(header_value == "example.com");
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: keep-alive\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .GET);
        assert(client.request.uri == "/");
        assert(client.request.body.count == 0);

        error, header_value := get_header(client.request.headers, "Host");
        assert(!error);
        assert(header_value == "example.com");

        error, header_value = get_header(client.request.headers, "Connection");
        assert(!error);
        assert(header_value == "keep-alive");
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\nContent-Length: 5\r\n\r\nHello");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .GET);
        assert(client.request.uri == "/");
        assert(client.request.body == "Hello");
    }

    {
        client := prepare_client("HEAD / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .HEAD);
    }

    {
        client := prepare_client("POST / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .POST);
    }

    {
        client := prepare_client("PUT / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .PUT);
    }

    {
        client := prepare_client("DELETE / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .DELETE);
    }

    {
        client := prepare_client("CONNECT / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .CONNECT);
    }

    {
        client := prepare_client("OPTIONS / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .OPTIONS);
    }

    {
        client := prepare_client("TRACE / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .TRACE);
    }

    {
        client := prepare_client("PATCH / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.method == .PATCH);
    }

    {
        client := prepare_client("GET /home HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.uri == "/home");
    }

    {
        client := prepare_client("GET /home/user?name=abc&home=def HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.uri == "/home/user?name=abc&home=def");
    }

    {
        client := prepare_client("NEVER / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Error);
    }

    {
        client := prepare_client("GET / HTTP/2\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Error);
    }

    {
        client := prepare_client("GET/ HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Error);
    }

    {
        client := prepare_client("GET/HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Error);
    }

    {
        client := prepare_client("GET /HTTP/1.1\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Error);
    }

    {
        client := prepare_client("G");
        result := parse_request(*client);
        assert(result == .Need_More_Data);
    }

    {
        client := prepare_client("GET");
        result := parse_request(*client);
        assert(result == .Need_More_Data);
    }

    {
        client := prepare_client("GET\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Error);
    }

    {
        client := prepare_client("GET /\r\n\r\n");
        result := parse_request(*client);
        assert(result == .Error);
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\nHos");
        result := parse_request(*client);
        assert(result == .Need_More_Data);
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\nHost:");
        result := parse_request(*client);
        assert(result == .Need_More_Data);
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\nHost: exa");
        result := parse_request(*client);
        assert(result == .Need_More_Data);
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\nHost: example.com\r\n");
        result := parse_request(*client);
        assert(result == .Need_More_Data);
    }

    {
        client := prepare_client("GET / HTTP/1.1\r\nContent-Length: 3\r\n\r\nHello");
        result := parse_request(*client);
        assert(result == .Success);
        assert(client.request.body == "Hel");
    }
}

#run {
    {
        error, result := decode_uri("%20");
        assert(!error);
        assert(result == " ");
    }

    {
        error, result := decode_uri("abc%20123");
        assert(!error);
        assert(result == "abc 123");
    }

    {
        error, result := decode_uri("%21abc%20123%22");
        assert(!error);
        assert(result == "!abc 123\"");
    }

    {
        error, result := decode_uri("abc123");
        assert(!error);
        assert(result == "abc123");
    }

    {
        error, result := decode_uri("%");
        assert(error);
        assert(result == "");
    }

    {
        error, result := decode_uri("%2");
        assert(error);
        assert(result == "");
    }

    {
        error, result := decode_uri("%%");
        assert(error);
        assert(result == "");
    }

    {
        error, result := decode_uri("abc%");
        assert(error);
        assert(result == "");
    }

    {
        error, result := decode_uri("%abc");
        assert(error);
        assert(result == "");
    }

    {
        error, result := decode_uri("%20%2a");
        assert(error);
        assert(result == "");
    }

    {
        error, result := decode_uri("");
        assert(!error);
        assert(result == "");
    }
}