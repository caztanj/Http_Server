# HTTP Server for Jai

This is an HTTP server written in Jai for Jai. It is not complete and there are almost certainly bugs!

## Features

- Partial HTTP/1.1
- Linux (epoll)
- Windows (Winsock2)
- TLS (LibreSSL)

## Compile LibreSSL and Generate Bindings

If you want to use TLS you need to compile LibreSSL and generate bindings for it. Simply run `jai generate.jai - -compile`.

You need to have CMake and Ninja installed.

## Linux

The Linux backend uses epoll and LibreSSL.

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