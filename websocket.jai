is_web_socket_upgrade :: (request: *Http_Request) -> bool {
    upgrade, error := get_header(request.headers, "Upgrade");
    if error then return false;

    if !equal_nocase(upgrade, "websocket") then return false;

    sec_web_socket_version:, error = get_header(request.headers, "Sec-WebSocket-Version");
    if error then return false;

    if !equal_nocase(sec_web_socket_version, "13") then return false;

    sec_web_socket_key:, error = get_header(request.headers, "Sec-WebSocket-Key");
    if error then return false;

    return true;
}

perform_web_socket_upgrade :: (message: Message) -> error: bool {
    sec_web_socket_key, error := get_header(message.http_request.headers, "Sec-WebSocket-Key");
    if error then return true;

    key_magic := join(sec_web_socket_key, WEB_SOCKET_MAGIC,, temp);

    // @Todo: We don't want to depend on LibreSSL here.
    hash: [LibreSSL.SHA_DIGEST_LENGTH] u8;
    LibreSSL.SHA1(key_magic.data, xx key_magic.count, hash.data);

    accept := base64_encode(xx hash,, temp);

    response := get_response(message);

    response.status = .Switching_Protocols;

    set_header(*response.headers, "Upgrade", "websocket");
    set_header(*response.headers, "Connection", "Upgrade");
    set_header(*response.headers, "Sec-WebSocket-Accept", accept);

    send_response(response);

    message.client.phase = .Transitioning_To_Web_Socket;

    return false;
}

send_web_socket_text :: (message: Message, text: string) {
    frame := Web_Socket_Frame.{
        fin = true,
        opcode = .Data_Frame_Text,
        masked = false,
        payload_length = xx text.count,
        payload = xx text,
    };

    chunk := array_add(*message.client.chunks_to_send);

    t     := chunk.buffer.data;
    max_t := t + chunk.buffer.count;

    if frame.fin {
        t.* = 0b10000000;
    }

    t.* |= xx frame.opcode;

    t += 1;
    assert(t < max_t);

    if frame.payload_length < 126 {
        t.* = xx frame.payload_length;

        t += 1;
        assert(t < max_t);
    } else {
        t.* = 127;

        t += 1;
        assert(t < max_t);

        (cast(*u64) t).* = frame.payload_length;

        t += 8;
        assert(t < max_t);
    }

    chunk.bytes_to_send = t - chunk.buffer.data;

    t     = frame.payload.data;
    max_t = t + frame.payload.count;

    done := false;
    while !done {
        chunk := array_add(*message.client.chunks_to_send);
        count := min(chunk.buffer.count, max_t - t);

        memcpy(chunk.buffer.data, t, count);

        chunk.bytes_to_send = count;

        t += count;

        done = t == max_t;
    }

    send_data_to_client(message.client);
}

#scope_module

parse_web_socket_frame :: (request: *Message) -> Web_Socket_Frame, error: bool #must {
    t     := request.raw.data;
    max_t := t + request.raw_count;

    frame: Web_Socket_Frame;

    frame.fin = xx t.* & 0b10000000;
    frame.opcode = xx t.* & 0b00001111;

    t += 1;
    if t >= max_t then return .{}, true;

    frame.masked = xx t.* & 0b10000000;
    frame.payload_length = t.* & 0b01111111;

    t += 1;
    if t >= max_t then return .{}, true;

    if frame.payload_length == 126 {
        frame.payload_length = t.* << 8;

        t += 1;
        if t >= max_t then return .{}, true;

        frame.payload_length |= t.*;

        t += 1;
        if t >= max_t then return .{}, true;
    } else if frame.payload_length == 127 {
        frame.payload_length = cast(u64) (t + 2).*;

        t += 8;
        if t >= max_t then return .{}, true;
    }

    if frame.masked {
        memcpy(frame.masking_key.data, t, 4);

        t += 4;
        if t >= max_t then return .{}, true;
    }

    frame.payload.data = t;
    frame.payload.count = xx frame.payload_length;

    if frame.masked {
        for i: 0..frame.payload_length - 1 {
            frame.payload[i] ^= frame.masking_key[i % 4];
        }
    }

    return frame, false;
}

Web_Socket_Opcode :: enum u8 {
    Continuation        :: 0;
    Data_Frame_Text     :: 1;
    Data_Frame_Binary   :: 2;
    Control_Frame_Close :: 8;
    Control_Frame_Ping  :: 9;
    Control_Frame_Pong  :: 10;
}

Web_Socket_Frame :: struct {
    fin: bool;
    opcode: Web_Socket_Opcode;
    masked: bool;
    payload_length: u64;
    masking_key: [4] u8;
    payload: [] u8;
}

WEB_SOCKET_MAGIC :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";