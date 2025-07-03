is_valid_utf8 :: (bytes: [] u8) -> bool {
    i := 0;
    while i < bytes.count {
        byte := bytes[i];
        remaining_bytes: int;

        if (byte & 0x80) == 0 {
            // 1-byte character: 0xxxxxxx
            remaining_bytes = 0;
        } else if (byte & 0xE0) == 0xC0 {
            // 2-byte character: 110xxxxx 10xxxxxx
            if byte < 0xC2 return false; // overlong encoding
            remaining_bytes = 1;
        } else if (byte & 0xF0) == 0xE0 {
            // 3-byte character: 1110xxxx 10xxxxxx 10xxxxxx
            remaining_bytes = 2;
            if i + 2 >= bytes.count return false;
            byte2 := bytes[i + 1];
            if byte == 0xE0 && (byte2 & 0xE0) != 0xA0 return false; // overlong
            if byte == 0xED && (byte2 & 0xE0) == 0xA0 return false; // surrogate
        } else if (byte & 0xF8) == 0xF0 {
            // 4-byte character: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
            if byte > 0xF4 return false; // max valid UTF-8 is U+10FFFF
            if byte == 0xF0 && (bytes[i + 1] & 0xF0) == 0x80 return false; // overlong
            if byte == 0xF4 && (bytes[i + 1] & 0xF0) > 0x8F return false; // beyond U+10FFFF
            remaining_bytes = 3;
        } else {
            return false; // invalid first byte
        }

        // Check continuation bytes
        if i + remaining_bytes >= bytes.count return false;
        for j: 1..remaining_bytes {
            if (bytes[i + j] & 0xC0) != 0x80 return false;
        }

        i += remaining_bytes + 1;
    }

    return true;
}