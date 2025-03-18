create_context :: () -> *SSL_CTX {
    method := TLS_server_method();
    ctx := SSL_CTX_new(method);
    if !ctx {
        ERR_print_errors_fp(POSIX.stderr);
        return null;
    }

    return ctx;
}

configure_context :: (ctx: *SSL_CTX, certificate_file: string, private_key_file: string) -> error: bool #must {
    if SSL_CTX_use_certificate_file(ctx, temp_c_string(certificate_file), SSL_FILETYPE_PEM) <= 0 {
        ERR_print_errors_fp(POSIX.stderr);
        return true;
    }

    if SSL_CTX_use_PrivateKey_file(ctx, temp_c_string(private_key_file), SSL_FILETYPE_PEM) <= 0 {
        ERR_print_errors_fp(POSIX.stderr);
        return true;
    }

    return false;
}

SSL        :: struct {};
SSL_CTX    :: struct {};
SSL_METHOD :: struct {};

SSL_new     :: (ctx: *SSL_CTX) -> *SSL #foreign libssl;
SSL_CTX_new :: (method: *SSL_METHOD) -> *SSL_CTX #foreign libssl;

TLS_server_method :: () -> *SSL_METHOD #foreign libssl;

ERR_print_errors_fp :: (fp: *POSIX.FILE) -> void #foreign libssl;

SSL_CTX_use_certificate_file :: (ctx: *SSL_CTX, file: *u8, type: s32) -> s32 #foreign libssl;
SSL_CTX_use_PrivateKey_file  :: (ctx: *SSL_CTX, file: *u8, type: s32) -> s32 #foreign libssl;

X509_FILETYPE_PEM :: 1;
SSL_FILETYPE_PEM  :: X509_FILETYPE_PEM;

SSL_set_fd :: (s: *SSL, fd: s32) -> s32 #foreign libssl;
SSL_accept :: (s: *SSL) -> s32 #foreign libssl;
SSL_read   :: (ssl: *SSL, buf: *void, num: s32) -> s32 #foreign libssl;
SSL_write  :: (ssl: *SSL, buf: *void, num: s32) -> s32 #foreign libssl;

SSL_shutdown :: (s: *SSL) -> s32 #foreign libssl;
SSL_free     :: (ssl: *SSL) -> void #foreign libssl;
SSL_CTX_free :: (ctx: *SSL_CTX) -> void #foreign libssl;

libssl    :: #system_library "libssl";
libcrypto :: #system_library,link_always "libcrypto";