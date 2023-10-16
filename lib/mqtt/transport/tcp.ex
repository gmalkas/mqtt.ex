defmodule MQTT.Transport.TCP do
  require Logger

  alias MQTT.TransportError

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

    with {:ok, socket} <- :gen_tcp.connect(host, port, Keyword.merge(opts, @transport_opts)) do
      {:ok, socket}
    else
      error -> wrap_error(error)
    end
  end

  def recv(socket, byte_count, timeout) do
    with {:ok, packet} <- :gen_tcp.recv(socket, byte_count, timeout) do
      {:ok, socket, packet}
    else
      error -> wrap_error(error)
    end
  end

  def send(socket, payload) do
    Logger.debug(
      "socket=#{inspect(socket)}, action=send, size=#{byte_size(payload)}, data=#{Base.encode16(payload)}"
    )

    with :ok <- :gen_tcp.send(socket, payload) do
      {:ok, socket}
    else
      error -> wrap_error(error)
    end
  end

  defp wrap_error({:error, reason}), do: {:error, %TransportError{reason: reason}}
  defp wrap_error(other), do: other
end
