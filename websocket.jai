is_websocket_upgrade :: (request: *Http_Request) -> bool {
    upgrade, error := get_header(request.headers, "Upgrade");
    if error then return false;

    if !equal_nocase(upgrade, "websocket") then return false;

    sec_websocket_version:, error = get_header(request.headers, "Sec-WebSocket-Version");
    if error then return false;

    if !equal_nocase(sec_websocket_version, "13") then return false;

    sec_websocket_key:, error = get_header(request.headers, "Sec-WebSocket-Key");
    if error then return false;

    return true;
}

perform_websocket_upgrade :: (request: *Http_Request) -> error: bool {
    sec_websocket_key, error := get_header(request.headers, "Sec-WebSocket-Key");
    if error then return true;

    key_magic := join(sec_websocket_key, WEBSOCKET_MAGIC,, temp);

    // @Todo: We don't want to depend on LibreSSL here.
    hash: [LibreSSL.SHA_DIGEST_LENGTH] u8;
    LibreSSL.SHA1(key_magic.data, xx key_magic.count, hash.data);

    accept := base64_encode(xx hash,, temp);

    response := get_response(request);

    response.status = .Switching_Protocols;

    set_header(*response.headers, "Upgrade", "websocket");
    set_header(*response.headers, "Connection", "Upgrade");
    set_header(*response.headers, "Sec-WebSocket-Accept", accept);

    send_response(response);

    return false;
}

#scope_module

WEBSOCKET_MAGIC :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";