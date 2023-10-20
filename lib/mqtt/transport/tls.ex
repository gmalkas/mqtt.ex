defmodule MQTT.Transport.TLS do
  require Logger

  alias MQTT.TransportError

  @default_port 8883
  @default_versions [:"tlsv1.3", :"tlsv1.2"]

  @allowed_options [
    :verify,
    :verify_fun,
    :cacerts,
    :cacertfile,
    :cert,
    :certfile,
    :key,
    :keyfile,
    :password,
    :cert_keys,
    :keepalive,
    :ip,
    :ifaddr,
    :nodelay
  ]

  @tls_options [
    alpn_advertised_protocols: ["mqtt"],
    depth: 4,
    reuse_sessions: true,
    secure_renegotiate: true,
    versions: @default_versions
  ]

  @enforced_options [active: false, mode: :binary, packet: :raw] ++ @tls_options

  def close(socket) do
    wrap_error(:ssl.close(socket))
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

  def data_received(socket, {:ssl, socket, data}) do
    {:ok, socket, data}
  end

  def data_received(_, _), do: :unknown

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

  def set_mode(socket, mode) do
    active =
      case mode do
        :active -> :once
        :passive -> false
      end

    with :ok <- :ssl.setopts(socket, active: active) do
      {:ok, socket}
    else
      error -> wrap_error(error)
    end
  end

  defp do_connect(host, port, options) do
    case :ssl.connect(host, port, options) do
      {:ok, socket} -> {:ok, socket}
      error -> wrap_error(error)
    end
  end

  defp wrap_error({:error, reason}), do: {:error, %TransportError{reason: reason}}
  defp wrap_error(other), do: other
end
