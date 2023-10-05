defmodule MQTT.Transport.TCP do
  require Logger

  @transport_opts [
    :binary,
    active: false,
    keepalive: true,
    nodelay: true
  ]

  def close(socket) do
    :gen_tcp.close(socket)
  end

  def connect(host, port, opts) when is_binary(host) do
    host = String.to_charlist(host)

    :gen_tcp.connect(host, port, Keyword.merge(opts, @transport_opts))
  end

  def recv(socket, byte_count, timeout) do
    :gen_tcp.recv(socket, byte_count, timeout)
  end

  def send(socket, payload) do
    Logger.debug(
      "socket=#{inspect(socket)}, action=send, size=#{byte_size(payload)}, data=#{Base.encode16(payload)}"
    )

    :ok = :gen_tcp.send(socket, payload)
  end
end
