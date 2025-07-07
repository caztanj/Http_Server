# HTTP Server for Jai

This is an HTTP server written in Jai for Jai.

## Features

- HTTP/1.1
- Web Sockets
- Linux (epoll)
- Windows (Winsock2)
- macOS (kqueue)
- TLS (LibreSSL)
- Router

## Compile LibreSSL and Generate Bindings

If you want to use TLS you need to compile LibreSSL and generate bindings for it. Simply run `jai generate.jai - -compile`.

You need to have CMake and Ninja installed.

## Linux

The Linux backend uses epoll and LibreSSL.

An additional io_uring backend will be added some time in the future.

## Windows

The Windows backend uses Winsock2 and LibreSSL.

An additional IOCP backend will be added some time in the future.

## macOS

The macOS backend uses kqueue and LibreSSL.

## TODO

- Windows
  - IOCP
- Router
  - Parameters
- HTTP/2
- HTTP/3

## Contributions

Feel free to open a pull request with your changes!