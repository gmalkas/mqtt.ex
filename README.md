# MQTT.ex

## Introduction

This project is under active development and aims at providing a client and
server Elixir implementations of the MQTT protocol.

Here are the objectives, in order of importance:
- Spec-compliant
  - Full support for MQTT 3.1, 3.1.1 and MQTT 5
- Easy-to-use:
    - Idiomatic Elixir
    - Surprise-free: if you are familiar with the MQTT spec or have worked with MQTT clients/servers before, you should not be surprised by this library.
    - Support for both async and sync APIs
- Error Handling: no crash, return meaningful errors
- Performance
- Introspection
- Telemetry

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
    - [ ] Event-driven API
    - [ ] Server redirection
    - [ ] Receive Maximum
    - [ ] Maximum Packet Size
    - [ ] Request/Response
    - [ ] Send Disconnect with proper reason code on error
    - [ ] Auto-reconnect with backoff
    - [ ] Packet encoding validation
    - [ ] UTF8 validation
    - [ ] Support for AUTH packet
    - [ ] Support all reason codes
    - [ ] Support all properties
    - [ ] Add support for MQTT v3.1.1
    - [ ] Add support for MQTT v3.1
    - [ ] Transport over Unix sockets
    - [ ] Secure default ciphers for TLS transport
