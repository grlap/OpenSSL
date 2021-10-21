function test_server()
    x509_certificate = X509Certificate()

    evp_pkey = EvpPKey(rsa_generate_key())
    x509_certificate.public_key = evp_pkey

    x509_name = X509Name()
    add_entry(x509_name, "C", "US")
    add_entry(x509_name, "ST", "Isles of Redmond")
    add_entry(x509_name, "CN", "www.redmond.com")

    adjust(x509_certificate.time_not_before, Second(0))
    adjust(x509_certificate.time_not_after, Year(1))

    x509_certificate.subject_name = x509_name
    x509_certificate.issuer_name = x509_name

    sign_certificate(x509_certificate, evp_pkey)

    server_socket = listen(5000)
    accepted_socket = accept(server_socket)

    # Create and configure server SSLContext.
    ssl_ctx = OpenSSL.SSLContext(OpenSSL.TLSv12ServerMethod())
    _ = OpenSSL.ssl_set_options(ssl_ctx, OpenSSL.SSL_OP_NO_COMPRESSION)
    
    OpenSSL.ssl_set_ciphersuites(ssl_ctx, "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256")
    OpenSSL.ssl_use_certificate(ssl_ctx, x509_certificate)
    OpenSSL.ssl_use_private_key(ssl_ctx, evp_pkey)

    ssl_stream = SSLStream(ssl_ctx, accepted_socket, accepted_socket)

    OpenSSL.accept(ssl_stream)

    bytes_available = bytesavailable(ssl_stream)
    request = read(ssl_stream, bytes_available)
    reply = "reply: $(String(request))"

    #TODO check available bytes

    write(ssl_stream, reply)

    close(ssl_stream)
    finalize(ssl_ctx)
    return nothing
end

function test_client()
    tcp_stream = connect(5000)

    ssl_ctx = OpenSSL.SSLContext(OpenSSL.TLSv12ClientMethod())
    ssl_options = OpenSSL.ssl_set_options(ssl_ctx, OpenSSL.SSL_OP_NO_COMPRESSION)

    # Create SSL stream.
    ssl_stream = SSLStream(ssl_ctx, tcp_stream, tcp_stream)

    #TODO expose connect
    OpenSSL.connect(ssl_stream)

    # Verify the server certificate.
    x509_server_cert = OpenSSL.get_peer_certificate(ssl_stream)

    @test String(x509_server_cert.issuer_name) == "/C=US/ST=Isles of Redmond/CN=www.redmond.com"
    @test String(x509_server_cert.subject_name) == "/C=US/ST=Isles of Redmond/CN=www.redmond.com"

    request_str = "GET / HTTP/1.1\r\nHost: localhost\r\nUser-Agent: curl\r\nAccept: */*\r\n\r\nRequest_body."

    written = unsafe_write(ssl_stream, pointer(request_str), length(request_str))

    @test length(request_str) == written

    response_str = String(read(ssl_stream))

    @test response_str == "reply: $request_str"

    close(ssl_stream)
    finalize(ssl_ctx)
    return nothing
end
