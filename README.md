# MQTT.ex

Client and Server implementations of the [MQTT protocol](https://mqtt.org/),
in Elixir.

:warning: This project is under **active** development and APIs may change
at any time.

## Introduction

Here are the objectives, in order of importance:
- Spec-compliant
  - Full support for MQTT v3.1, v3.1.1 and v5
- Easy-to-use:
    - Idiomatic Elixir
    - Surprise-free: mirror domain language of specification
    - Support for both async and sync APIs
- Error Handling: no crash, return meaningful errors
- Telemetry
- Introspection
- Performance

## Installation

## Usage: Client


### Connecting to a server

### Publishing messages

### Receiving messages

### Publishing with QoS 1

### Publishing with QoS 2

### Connecting over TLS

### Connecting over Websockets

### Enhanced Authentication

## Contributing

## License

## Roadmap

- Client
    - [x] Retain
    - [x] Will message
    - [x] Shared Subscriptions
    - [x] Username/password authentication
    - [x] Transport over TLS
    - [x] QoS 1
    - [x] Topic Alias
    - [x] Topic Alias Maximum
    - [x] QoS 2
    - [x] Transport over WebSocket
    - [x] IPv6
    - [x] Keep Alive
    - [x] Server redirection
    - [x] Auto-reconnect with configurable backoff
    - [x] Support for AUTH packet and enhanced authentication flow
    - [ ] Event-driven API
    - [ ] Receive Maximum
    - [ ] Maximum Packet Size
    - [ ] Send Disconnect with proper reason code on error
    - [ ] Packet encoding validation
    - [ ] UTF-8 validation
    - [ ] Support all reason codes
    - [ ] Support all properties
    - [ ] Add support for MQTT v3.1.1
    - [ ] Add support for MQTT v3.1
    - [ ] Transport over Unix sockets
    - [ ] Default CA store for TLS transport
    - [ ] Secure default ciphers for TLS transport
