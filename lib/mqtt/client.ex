defmodule MQTT.Client do
  require Logger

  alias MQTT.ClientConn, as: Conn
  alias MQTT.{Packet, PacketBuilder, PacketDecoder, Transport}

  @default_read_timeout_ms 500

  def connect(host, client_id, options \\ []) do
    transport = Keyword.get(options, :transport, Transport.TCP)
    transport_opts = Keyword.get(options, :transport_opts, [])
    port = Keyword.get(options, :port, default_port(transport))

    user_name = Keyword.get(options, :user_name)
    password = Keyword.get(options, :password)
    will_message = Keyword.get(options, :will_message)

    packet_options =
      Keyword.take(options, [:keep_alive])
      |> Keyword.put(:client_id, client_id)

    packet = PacketBuilder.Connect.new(packet_options)

    packet =
      if !is_nil(user_name) do
        PacketBuilder.Connect.with_user_name(packet, user_name)
      else
        packet
      end

    packet =
      if !is_nil(password) do
        PacketBuilder.Connect.with_password(packet, password)
      else
        packet
      end

    packet =
      case will_message do
        nil ->
          packet

        {topic, payload} ->
          PacketBuilder.Connect.with_will_message(packet, topic, payload)

        {topic, payload, options} ->
          PacketBuilder.Connect.with_will_message(packet, topic, payload, options)
      end

    encoded_packet = Packet.Connect.encode!(packet)

    Logger.info("host=#{host}, port=#{port}, action=connect")

    case transport.connect(host, port, transport_opts) do
      {:ok, socket} ->
        conn =
          send_packet!(Conn.connecting(transport, host, port, socket, packet), encoded_packet)

        {:ok, conn}
    end
  end

  def disconnect(%Conn{} = conn, reason_code \\ :normal_disconnection) do
    packet = PacketBuilder.Disconnect.new(reason_code)
    encoded_packet = Packet.Disconnect.encode!(packet)

    conn = send_packet!(conn, encoded_packet)
    :ok = conn.transport.close(conn.socket)

    Conn.disconnect(conn)
  end

  def ping(%Conn{} = conn) do
    packet = PacketBuilder.Pingreq.new()
    encoded_packet = Packet.Pingreq.encode!(packet)

    conn = send_packet!(conn, encoded_packet)

    {:ok, conn}
  end

  def publish(%Conn{} = conn, topic, payload, options \\ []) do
    qos = Keyword.get(options, :qos, 0)
    retain? = Keyword.get(options, :retain?, false)

    {packet_identifier, conn} =
      if qos > 0 do
        Conn.next_packet_identifier(conn)
      else
        {nil, conn}
      end

    if retain? && !Conn.retain_available?(conn) do
      {:error, :retain_not_available}
    else
      packet = PacketBuilder.Publish.new(packet_identifier, topic, payload, options)
      encoded_packet = Packet.Publish.encode!(packet)

      conn = send_packet!(conn, encoded_packet)

      {:ok, conn}
    end
  end

  def read_next_packet(%Conn{} = conn) do
    with {:ok, packet, buffer} <- do_read_next_packet(conn, conn.read_buffer),
         {:ok, conn} <- Conn.handle_packet_from_server(conn, packet, buffer) do
      {:ok, packet, conn}
    end
  end

  def subscribe(%Conn{} = conn, topic_filters) when is_list(topic_filters) do
    {packet_identifier, conn} = Conn.next_packet_identifier(conn)

    packet = PacketBuilder.Subscribe.new(packet_identifier, topic_filters)
    encoded_packet = Packet.Subscribe.encode!(packet)

    conn = send_packet!(conn, encoded_packet)

    {:ok, conn}
  end

  def tick(%Conn{} = conn) do
    if Conn.should_ping?(conn) do
      ping(conn)
    else
      {:ok, conn}
    end
  end

  def unsubscribe(%Conn{} = conn, topic_filters) when is_list(topic_filters) do
    {packet_identifier, conn} = Conn.next_packet_identifier(conn)

    packet = PacketBuilder.Unsubscribe.new(packet_identifier, topic_filters)
    encoded_packet = Packet.Unsubscribe.encode!(packet)

    conn = send_packet!(conn, encoded_packet)

    {:ok, conn}
  end

  # HELPERS

  defp send_packet!(conn, packet) do
    :ok = conn.transport.send(conn.socket, packet)

    Conn.packet_sent(conn)
  end

  defp do_read_next_packet(conn, buffer) do
    if byte_size(buffer) > 0 do
      case PacketDecoder.decode(buffer) do
        {:ok, packet, buffer} -> {:ok, packet, buffer}
        {:error, :incomplete} -> do_read_next_packet_from_socket(conn, buffer)
      end
    else
      do_read_next_packet_from_socket(conn, buffer)
    end
  end

  defp do_read_next_packet_from_socket(conn, buffer) do
    case conn.transport.recv(conn.socket, 0, @default_read_timeout_ms) do
      {:ok, data} ->
        Logger.debug(
          "socket=#{inspect(conn.socket)}, action=read, size=#{byte_size(data)}, data=#{Base.encode16(data)}"
        )

        buffer = buffer <> data

        case PacketDecoder.decode(buffer) do
          {:ok, packet, buffer} -> {:ok, packet, buffer}
          {:error, :incomplete} -> do_read_next_packet_from_socket(conn, buffer)
        end

      {:error, :timeout} ->
        {:error, :timeout}
    end
  end

  defp default_port(Transport.TCP), do: 1883
  defp default_port(Transport.TLS), do: 8883
end
