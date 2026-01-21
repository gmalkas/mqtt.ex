defmodule MQTT.Transport.TCP do
  require Logger

  alias MQTT.TransportError

  @default_port 1883
  @allowed_options [:keepalive, :ip, :ifaddr, :nodelay]
  @enforced_options [
    active: false,
    mode: :binary,
    packet: :raw
  ]

  def close(socket) do
    :gen_tcp.close(socket)
  end

  def connect(host, opts) when is_binary(host) do
    connect({host, @default_port}, opts)
  end

  def connect({host, port}, opts) when is_binary(host) and is_integer(port) do
    host = String.to_charlist(host)

    hostname_or_ip_address =
      case :inet.parse_address(host) do
        {:ok, ip_address} -> ip_address
        {:error, :einval} -> host
      end

    use_ipv6? = Keyword.get(opts, :inet6, false)

    options =
      opts
      |> Keyword.take(@allowed_options)
      |> Keyword.merge(@enforced_options)

    if use_ipv6? do
      case do_connect(hostname_or_ip_address, port, [:inet6 | options]) do
        {:ok, socket} ->
          {:ok, socket}

        _error ->
          # We fallback to IPv4 if IPv6 does not work. This assumes a hostname
          # was provided rather than a IPv6 address as otherwise retrying is
          # not going to help.
          do_connect(hostname_or_ip_address, port, options)
      end
    else
      do_connect(hostname_or_ip_address, port, options)
    end
  end

  def data_received(socket, {:tcp, socket, data}) do
    {:ok, socket, data}
  end

  def data_received(socket, {:tcp_closed, socket}) do
    {:ok, :transport_closed}
  end

  def data_received(_, _), do: :unknown

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

  def set_mode(socket, mode) do
    active =
      case mode do
        :active -> :once
        :passive -> false
      end

    with :ok <- :inet.setopts(socket, active: active) do
      {:ok, socket}
    else
      error -> wrap_error(error)
    end
  end

  defp do_connect(host, port, options) do
    case :gen_tcp.connect(host, port, options) do
      {:ok, socket} -> {:ok, socket}
      error -> wrap_error(error)
    end
  end

  defp wrap_error({:error, reason}), do: {:error, %TransportError{reason: reason}}
  defp wrap_error(other), do: other
end
