# HTTP Server for Jai

This is an HTTP server written in Jai for Jai. It is not complete and there are almost certainly bugs!

## Features

- Partial HTTP/1.1
- Linux (epoll)
- Windows (Winsock2)
- TLS (OpenSSL)

## Linux

The Linux backend uses epoll and OpenSSL.

An additional io_uring backend will be added some time in the future.

## Windows

The Windows backend uses Winsock2 and does not support TLS (yet).

An additional IOCP backend will be added some time in the future.

## TODO

- Windows
  - IOCP
  - TLS
- macOS
  - kqueue
  - TLS
- Router
- Complete HTTP/1.1
- HTTP/2
- HTTP/3
- WebSockets

## Contributions

Feel free to open a pull request with your changes!