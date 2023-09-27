defmodule MQTT.Client do
  require Logger

  alias MQTT.ClientConn, as: Conn
  alias MQTT.{Packet, PacketBuilder, PacketDecoder}

  @default_port 1883
  @default_read_timeout_ms 500

  def connect(ip_address, client_id, options \\ []) do
    port = Keyword.get(options, :port, @default_port)

    packet = PacketBuilder.Connect.new(client_id)
    encoded_packet = Packet.Connect.encode!(packet)

    Logger.info("ip_address=#{ip_address}, port=#{port}, action=connect")

    case tcp_connect(ip_address, port) do
      {:ok, socket} ->
        send_to_socket!(socket, encoded_packet)

        {:ok, Conn.connecting(ip_address, port, client_id, socket)}
    end
  end

  def disconnect(%Conn{} = conn) do
    packet = PacketBuilder.Disconnect.new(:normal_disconnection)
    encoded_packet = Packet.Disconnect.encode!(packet)

    send_to_socket!(conn.socket, encoded_packet)
    close_socket!(conn.socket)

    Conn.disconnect(conn)
  end

  def ping(%Conn{} = conn) do
    packet = PacketBuilder.Pingreq.new()
    encoded_packet = Packet.Pingreq.encode!(packet)

    send_to_socket!(conn.socket, encoded_packet)

    {:ok, conn}
  end

  def publish(%Conn{} = conn, topic, payload, options \\ []) do
    qos = Keyword.get(options, :qos, 0)

    {packet_identifier, conn} =
      if qos > 0 do
        Conn.next_packet_identifier(conn)
      else
        {nil, conn}
      end

    packet = PacketBuilder.Publish.new(packet_identifier, topic, payload, options)
    encoded_packet = Packet.Publish.encode!(packet)

    send_to_socket!(conn.socket, encoded_packet)

    {:ok, conn}
  end

  def read_next_packet(%Conn{} = conn) do
    with {:ok, packet, buffer} <- do_read_next_packet(conn.socket, conn.read_buffer),
         {:ok, conn} <- Conn.handle_packet_from_server(conn, packet, buffer) do
      {:ok, packet, conn}
    end
  end

  def subscribe(%Conn{} = conn, topic_filters) when is_list(topic_filters) do
    {packet_identifier, conn} = Conn.next_packet_identifier(conn)

    packet = PacketBuilder.Subscribe.new(packet_identifier, topic_filters)
    encoded_packet = Packet.Subscribe.encode!(packet)

    send_to_socket!(conn.socket, encoded_packet)

    {:ok, conn}
  end

  def unsubscribe(%Conn{} = conn, topic_filters) when is_list(topic_filters) do
    {packet_identifier, conn} = Conn.next_packet_identifier(conn)

    packet = PacketBuilder.Unsubscribe.new(packet_identifier, topic_filters)
    encoded_packet = Packet.Unsubscribe.encode!(packet)

    send_to_socket!(conn.socket, encoded_packet)

    {:ok, conn}
  end

  # HELPERS

  defp tcp_connect(ip_address, port) do
    {:ok, ip_address} =
      ip_address
      |> String.to_charlist()
      |> :inet.parse_address()

    :gen_tcp.connect(ip_address, port, [
      :binary,
      active: false,
      keepalive: true,
      nodelay: true
    ])
  end

  defp read_from_socket(socket) do
    :gen_tcp.recv(socket, 0, @default_read_timeout_ms)
  end

  defp send_to_socket!(socket, packet) do
    Logger.debug(
      "socket=#{inspect(socket)}, action=send, size=#{byte_size(packet)}, data=#{Base.encode16(packet)}"
    )

    :ok = :gen_tcp.send(socket, packet)
  end

  defp do_read_next_packet(socket, buffer) do
    case read_from_socket(socket) do
      {:ok, data} ->
        Logger.debug(
          "socket=#{inspect(socket)}, action=read, size=#{byte_size(data)}, data=#{Base.encode16(data)}"
        )

        buffer = buffer <> data

        case PacketDecoder.decode(buffer) do
          {:ok, packet, buffer} -> {:ok, packet, buffer}
          {:error, :incomplete_packet} -> do_read_next_packet(socket, buffer)
        end

      {:error, :timeout} ->
        {:error, :timeout}
    end
  end

  defp close_socket!(socket), do: :ok = :gen_tcp.close(socket)
end
