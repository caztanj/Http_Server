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

perform_web_socket_upgrade :: (server: *Http_Server, request: *Http_Request) -> error: bool {
    sec_web_socket_key, error := get_header(request.headers, "Sec-WebSocket-Key");
    if error then return true;

    key_magic := join(sec_web_socket_key, WEB_SOCKET_MAGIC,, temp);

    // @Todo: We don't want to depend on LibreSSL here.
    hash: [LibreSSL.SHA_DIGEST_LENGTH] u8;
    LibreSSL.SHA1(key_magic.data, xx key_magic.count, hash.data);

    accept := base64_encode(xx hash,, temp);

    response := make_response(request,, temp);

    response.status = .Switching_Protocols;

    set_header(*response.headers, "Upgrade", "websocket");
    set_header(*response.headers, "Connection", "Upgrade");
    set_header(*response.headers, "Sec-WebSocket-Accept", accept);

    client := find_client(server, request.id);
    if client == null then return true;

    client.phase = .Upgrading_To_Web_Socket;

    send_response(server, response);

    return false;
}

send_web_socket_text :: (server: *Http_Server, id: Socket.Socket, text: string) -> error: bool {
    client := find_client(server, id);
    if client == null then return true;

    frame := Web_Socket_Frame.{
        fin = true,
        opcode = .Data_Frame_Text,
        payload_length = xx text.count,
    };

    frame.payload.data = text.data;
    frame.payload.count = text.count;

    send_web_socket_frame(server, client, frame);

    return false;
}

send_web_socket_blob :: (server: *Http_Server, id: Socket.Socket, data: [] u8) -> error: bool {
    client := find_client(server, id);
    if client == null then return true;

    frame := Web_Socket_Frame.{
        fin = true,
        opcode = .Data_Frame_Binary,
        payload_length = xx data.count,
    };

    frame.payload.data = data.data;
    frame.payload.count = data.count;

    send_web_socket_frame(server, client, frame);

    return false;
}

Web_Socket_Frame :: struct {
    // @Todo: Remove this
    id: Socket.Socket;
    fin: bool;
    opcode: Web_Socket_Opcode;
    masked: bool;
    payload_length: u64;
    masking_key: [4] u8;
    payload: [..] u8;
}

Web_Socket_Message_Type :: enum {
    Text;
    Binary;
}

Web_Socket_Message :: struct {
    id: Socket.Socket;
    type: Web_Socket_Message_Type;
    frame: *Web_Socket_Frame; // @Todo: Give the user the message instead of the frame.
}

#scope_module

parse_web_socket_frame :: (client: *Http_Client) -> Web_Socket_Frame, error: bool #must {
    t     := client.request.raw.data;
    max_t := t + client.request.raw_count;

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
        frame.payload_length = t.*;
        frame.payload_length <<= 8;

        t += 1;
        if t >= max_t then return .{}, true;

        frame.payload_length |= t.*;

        t += 1;
        if t >= max_t then return .{}, true;
    } else if frame.payload_length == 127 {
        if (t + 7) >= max_t then return .{}, true;

        // @Robustness

        b1: u64 = t.*.(u64) << 56;
        b2: u64 = (t + 1).*.(u64) << 48;
        b3: u64 = (t + 2).*.(u64) << 40;
        b4: u64 = (t + 3).*.(u64) << 32;
        b5: u64 = (t + 4).*.(u64) << 24;
        b6: u64 = (t + 5).*.(u64) << 16;
        b7: u64 = (t + 6).*.(u64) << 8;
        b8: u64 = (t + 7).*.(u64);

        frame.payload_length = b1 | b2 | b3 | b4 | b5 | b6 | b7 | b8;

        t += 8;
        if t >= max_t then return .{}, true;
    }

    if frame.masked {
        if max_t - t < 4 then return .{}, true;

        memcpy(frame.masking_key.data, t, 4);

        t += 4;
        if frame.payload_length == 0 {
            if t != max_t then return .{}, true;
        } else if t >= max_t {
            return .{}, true;
        }
    }

    if max_t - t != xx frame.payload_length then return .{}, true;

    // @Todo: I think we are leaking this.
    array_reserve(*frame.payload, xx frame.payload_length);
    memcpy(frame.payload.data, t, xx frame.payload_length);
    frame.payload.count = xx frame.payload_length;

    if frame.masked && frame.payload_length > 0 {
        for i: 0..frame.payload_length - 1 {
            frame.payload[i] ^= frame.masking_key[i % 4];
        }
    }

    return frame, false;
}

send_web_socket_close_frame :: (server: *Http_Server, client: *Http_Client) {
    frame := Web_Socket_Frame.{
        fin = true,
        opcode = .Control_Frame_Close,
    };

    client.close_after_send = true;

    send_web_socket_frame(server, client, frame);
}

send_web_socket_frame :: (server: *Http_Server, client: *Http_Client, frame: Web_Socket_Frame) {
    chunk := array_add(*client.chunks_to_send);

    t     := chunk.buffer.data;
    max_t := t + chunk.buffer.count;

    if frame.fin {
        t.* = 0b10000000;
    }

    t.* |= xx frame.opcode;

    t += 1;
    assert(t < max_t);

    if frame.payload_length <= 125 {
        t.* = xx frame.payload_length;

        t += 1;
        assert(t < max_t);
    } else {
        if frame.payload_length <= 65535 {
            t.* = 126;

            t += 1;
            assert(t < max_t);

            t.* = xx (frame.payload_length & 0b1111111100000000) >> 8;

            t += 1;
            assert(t < max_t);

            t.* = xx frame.payload_length & 0b11111111;

            t += 1;
            assert(t < max_t);
        } else {
            t.* = 127;

            t += 1;
            assert(t < max_t);

            (t + 0).* = xx (frame.payload_length >> 56) & 0xFF;
            (t + 1).* = xx (frame.payload_length >> 48) & 0xFF;
            (t + 2).* = xx (frame.payload_length >> 40) & 0xFF;
            (t + 3).* = xx (frame.payload_length >> 32) & 0xFF;
            (t + 4).* = xx (frame.payload_length >> 24) & 0xFF;
            (t + 5).* = xx (frame.payload_length >> 16) & 0xFF;
            (t + 6).* = xx (frame.payload_length >> 8)  & 0xFF;
            (t + 7).* = xx  frame.payload_length        & 0xFF;

            t += 8;
            assert(t < max_t);
        }
    }

    chunk.bytes_to_send = t - chunk.buffer.data;

    t     = frame.payload.data;
    max_t = t + frame.payload.count;

    done := t == max_t;
    while !done {
        chunk := array_add(*client.chunks_to_send);
        count := min(chunk.buffer.count, max_t - t);

        memcpy(chunk.buffer.data, t, count);

        chunk.bytes_to_send = count;

        t += count;

        done = t == max_t;
    }

    send_data_to_client(server, client);
}

Web_Socket_Opcode :: enum u8 {
    Continuation        :: 0;
    Data_Frame_Text     :: 1;
    Data_Frame_Binary   :: 2;
    Control_Frame_Close :: 8;
    Control_Frame_Ping  :: 9;
    Control_Frame_Pong  :: 10;
}

Web_Socket_Status_Code :: enum {
    Normal_Closure               :: 1000;
    Going_Away                   :: 1001;
    Protocol_Error               :: 1002;
    Unsupported_Data             :: 1003;
    No_Code_Received             :: 1005;
    Connection_Closed_Abnormally :: 1006;
    Invalid_Payload_Data         :: 1007;
    Policy_Violated              :: 1008;
    Message_Too_Big              :: 1009;
    Unsupported_Extension        :: 1010;
    Internal_Server_Error        :: 1011;
    TLS_Handshake_Failure        :: 1015;
}

WEB_SOCKET_MAGIC :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";