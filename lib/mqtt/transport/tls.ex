defmodule MQTT.Transport.TLS do
  require Logger

  @default_versions [:"tlsv1.3", :"tlsv1.2"]
  @transport_opts [
    mode: :binary,
    active: false,
    keepalive: true,
    nodelay: true
  ]

  @tls_opts [
    alpn_advertised_protocols: ["mqtt"],
    depth: 4,
    reuse_sessions: true,
    secure_renegotiate: true,
    versions: @default_versions
  ]

  def close(socket) do
    :ssl.close(socket)
  end

  def connect(host, port, opts) when is_binary(host) do
    host = String.to_charlist(host)

    :ssl.connect(host, port, Keyword.merge(opts, @transport_opts ++ @tls_opts))
  end

  def recv(socket, byte_count, timeout) do
    :ssl.recv(socket, byte_count, timeout)
  end

  def send(socket, payload) do
    Logger.debug(
      "socket=#{inspect(socket)}, action=send, size=#{byte_size(payload)}, data=#{Base.encode16(payload)}"
    )

    :ok = :ssl.send(socket, payload)
  end
end
