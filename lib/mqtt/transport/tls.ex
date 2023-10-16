defmodule MQTT.Transport.TLS do
  require Logger

  alias MQTT.TransportError

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
    wrap_error(:ssl.close(socket))
  end

  def connect(host, port, opts) when is_binary(host) do
    host = String.to_charlist(host)

    with {:ok, socket} <-
           :ssl.connect(host, port, Keyword.merge(opts, @transport_opts ++ @tls_opts)) do
      {:ok, socket}
    else
      error -> wrap_error(error)
    end
  end

  def recv(socket, byte_count, timeout) do
    with {:ok, data} <- :ssl.recv(socket, byte_count, timeout) do
      {:ok, socket, data}
    else
      error -> wrap_error(error)
    end
  end

  def send(socket, payload) do
    Logger.debug(
      "socket=#{inspect(socket)}, action=send, size=#{byte_size(payload)}, data=#{Base.encode16(payload)}"
    )

    with :ok <- :ssl.send(socket, payload) do
      {:ok, socket}
    else
      error -> wrap_error(error)
    end
  end

  defp wrap_error({:error, reason}), do: {:error, %TransportError{reason: reason}}
  defp wrap_error(other), do: other
end
