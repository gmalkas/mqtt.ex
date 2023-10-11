defmodule MQTT.Client do
  require Logger

  alias MQTT.ClientConn, as: Conn
  alias MQTT.ClientSession, as: Session
  alias MQTT.{Error, Packet, PacketBuilder, PacketDecoder, Transport}

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

    Logger.info("host=#{host}, port=#{port}, action=connect")

    with {:ok, socket} <- transport.connect(host, port, transport_opts) do
      send_packet(
        Conn.connecting({transport, transport_opts}, host, port, socket, packet),
        packet
      )
    end
  end

  def disconnect(%Conn{} = conn, reason_code \\ :normal_disconnection) do
    packet = PacketBuilder.Disconnect.new(reason_code)

    with {:ok, conn} <- send_packet(conn, packet),
         :ok <- conn.transport.close(conn.socket) do
      Conn.disconnect(conn)
    end
  end

  def disconnect!(%Conn{} = conn) do
    with :ok <- conn.transport.close(conn.socket) do
      Conn.disconnect(conn)
    end
  end

  def ping(%Conn{} = conn) do
    packet = PacketBuilder.Pingreq.new()

    send_packet(conn, packet)
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

      send_packet(conn, packet)
    end
  end

  def read_next_packet(%Conn{} = conn) do
    with {:ok, packet, buffer} <- do_read_next_packet(conn, conn.read_buffer),
         {:ok, conn} <- Conn.handle_packet_from_server(conn, packet, buffer) do
      {:ok, packet, conn}
    end
  end

  def reconnect(%Conn{state: :disconnected} = conn) do
    connect_packet = PacketBuilder.Connect.with_clean_start(conn.connect_packet, false)

    Logger.info("host=#{conn.host}, port=#{conn.port}, action=reconnect")

    with {:ok, socket} <- conn.transport.connect(conn.host, conn.port, conn.transport_opts),
         {:ok, conn} <- send_packet(Conn.reconnecting(conn, socket), connect_packet) do
      case read_next_packet(conn) do
        {:ok, %Packet.Connack{} = packet, conn} ->
          if packet.flags.session_present? do
            republish_unacknowledged_messages(conn, packet)
          else
            {:ok, packet, Conn.destroy_session(conn)}
          end

        {:ok, _packet, conn} ->
          {:error, Error.protocol_error("unexpected packet received"), conn}
      end
    end
  end

  def subscribe(%Conn{} = conn, topic_filters) when is_list(topic_filters) do
    {packet_identifier, conn} = Conn.next_packet_identifier(conn)

    packet = PacketBuilder.Subscribe.new(packet_identifier, topic_filters)

    send_packet(conn, packet)
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

    send_packet(conn, packet)
  end

  # HELPERS

  defp send_packet(conn, packet) do
    with :ok <- conn.transport.send(conn.socket, Packet.encode!(packet)) do
      {:ok, Conn.packet_sent(conn, packet)}
    end
  end

  defp do_read_next_packet(conn, buffer) do
    if byte_size(buffer) > 0 do
      case PacketDecoder.decode(buffer) do
        {:ok, packet, buffer} -> {:ok, packet, buffer}
        {:error, :incomplete_packet} -> do_read_next_packet_from_socket(conn, buffer)
      end
    else
      do_read_next_packet_from_socket(conn, buffer)
    end
  end

  defp do_read_next_packet_from_socket(conn, buffer) do
    with {:ok, data} <- conn.transport.recv(conn.socket, 0, @default_read_timeout_ms) do
      Logger.debug(
        "socket=#{inspect(conn.socket)}, action=read, size=#{byte_size(data)}, data=#{Base.encode16(data)}"
      )

      buffer = buffer <> data

      case PacketDecoder.decode(buffer) do
        {:ok, packet, buffer} -> {:ok, packet, buffer}
        {:error, :incomplete_packet} -> do_read_next_packet_from_socket(conn, buffer)
        other_error -> other_error
      end
    end
  end

  defp default_port(Transport.TCP), do: 1883
  defp default_port(Transport.TLS), do: 8883

  defp republish_unacknowledged_messages(conn, packet) do
    conn.session
    |> Session.unacknowledged_packets()
    |> Enum.reduce_while(conn, fn packet, conn ->
      dup_packet = PacketBuilder.Publish.with_dup(packet, true)

      case send_packet(conn, dup_packet) do
        {:ok, conn} -> {:cont, conn}
        error -> {:halt, error}
      end
    end)
    |> case do
      %Conn{} = conn -> {:ok, packet, conn}
      error -> error
    end
  end
end
