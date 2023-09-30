# MQTT.ex

## Introduction

This project is under active development and aims at providing a client and
server Elixir implementations of the MQTT protocol.

Here are the objectives, in order of importance:
- Spec-compliant
  - Full support for MQTT 3.1.1 and MQTT 5
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
    - [ ] Retain
    - [ ] Will message
    - [ ] Shared Subscriptions
    - [ ] Server redirection
    - [ ] Session
    - [ ] QoS 1/2
    - [ ] Keep-alive
    - [ ] Receive Maximum
    - [x] Username/password authentication
    - [ ] Send Disconnect with proper reason code on error
    - [ ] Packet encoding validation
    - [ ] UTF8 validation
    - [ ] Support for AUTH packet
    - [ ] Support all reason codes
    - [ ] Support all properties
    - [ ] Transport over TLS
    - [ ] Authentication with TLS client certificate
    - [ ] Transport over WebSocket
    - [ ] Add support for MQTT v3.1.1
