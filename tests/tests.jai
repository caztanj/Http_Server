#run {
    // Parse HTTP/1.1 tests.

    prepare_client :: (request: string) -> Http_Client {
        client: Http_Client;
        array_resize(*client.buffer, 65535);
        memcpy(client.buffer.data, request.data, request.count);
        client.buffer_count = request.count;
        return client;
    }

    {
        // Valid request with no headers and no body.

        client := prepare_client("GET / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .GET);
        assert(client.request.uri == "/");
        assert(client.request.headers.count == 0);
        assert(client.request.body.count == 0);
    }

    {
        // Vald request with one header but no body.
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
        // Valid request with two headers but no body.
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
        // Valid request with Content-Length header and body.
        client := prepare_client("GET / HTTP/1.1\r\nContent-Length: 5\r\n\r\nHello");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .GET);
        assert(client.request.uri == "/");
        assert(client.request.body == "Hello");
    }

    {
        // Valid HEAD request with no headers and no body.
        client := prepare_client("HEAD / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .HEAD);
    }

    {
        // Valid POST request with no headers and no body.
        client := prepare_client("POST / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .POST);
    }

    {
        // Valid PUT request with no headers and no body.
        client := prepare_client("PUT / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .PUT);
    }

    {
        // Valid DELETE request with no headers and no body.
        client := prepare_client("DELETE / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .DELETE);
    }

    {
        // Valid CONNECT request with no headers and no body.
        client := prepare_client("CONNECT / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .CONNECT);
    }

    {
        // Valid OPTIONS request with no headers and no body.
        client := prepare_client("OPTIONS / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .OPTIONS);
    }

    {
        // Valid TRACE request with no headers and no body.
        client := prepare_client("TRACE / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .TRACE);
    }

    {
        // Vaid PATCH request with no headers and no body.
        client := prepare_client("PATCH / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.method == .PATCH);
    }

    {
        // Valid request with a simple URI but no headers and no body.
        client := prepare_client("GET /home HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.uri == "/home");
    }

    {
        // Valid request with a URI with query strings but no headers and no body.
        client := prepare_client("GET /home/user?name=abc&home=def HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Success);
        assert(client.request.uri == "/home/user?name=abc&home=def");
    }

    {
        // Invalid HTTP verb.
        client := prepare_client("NEVER / HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Error);
    }

    {
        // Invalid HTTP version.
        client := prepare_client("GET / HTTP/2\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Error);
    }

    {
        // No space between HTTP verb and URI.
        client := prepare_client("GET/ HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Error);
    }

    {
        // No space between HTTP verb and URI and no space between URI and HTTP version.
        client := prepare_client("GET/HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Error);
    }

    {
        // No space between URI and HTTP version.
        client := prepare_client("GET /HTTP/1.1\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Error);
    }

    {
        // Incomplete but start of valid request.
        client := prepare_client("G");
        result := parse_request(*client);

        assert(result == .Need_More_Data);
    }

    {
        // Incomplete but start of valid request.
        client := prepare_client("GET");
        result := parse_request(*client);

        assert(result == .Need_More_Data);
    }

    {
        // Missing URI and HTTP version.
        client := prepare_client("GET\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Error);
    }

    {
        // Missing HTTP version.
        client := prepare_client("GET /\r\n\r\n");
        result := parse_request(*client);

        assert(result == .Error);
    }

    {
        // Incomplete but start of valid request.
        client := prepare_client("GET / HTTP/1.1\r\nHos");
        result := parse_request(*client);

        assert(result == .Need_More_Data);
    }

    {
        // Incomplete but start of valid request.
        client := prepare_client("GET / HTTP/1.1\r\nHost:");
        result := parse_request(*client);

        assert(result == .Need_More_Data);
    }

    {
        // Incomplete but start of valid request.
        client := prepare_client("GET / HTTP/1.1\r\nHost: exa");

        result := parse_request(*client);
        assert(result == .Need_More_Data);
    }

    {
        // Incomplete but start of valid request.
        client := prepare_client("GET / HTTP/1.1\r\nHost: example.com\r\n");
        result := parse_request(*client);

        assert(result == .Need_More_Data);
    }

    {
        // Valid request with trailing data.
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