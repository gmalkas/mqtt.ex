defmodule MQTT.Client do
  require Logger

  alias MQTT.ClientConn, as: Conn
  alias MQTT.ClientSession, as: Session
  alias MQTT.{Error, Packet, PacketBuilder, PacketDecoder, Transport}

  @default_read_timeout_ms 500

  def connect(endpoint, client_id, options \\ []) do
    transport = Keyword.get(options, :transport, Transport.TCP)
    transport_opts = Keyword.get(options, :transport_opts, [])

    conn_options = Keyword.take(options, [:timeout])

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

    Logger.info("endpoint=#{inspect(endpoint)}, action=connect")

    with {:ok, handle} <- transport.connect(endpoint, transport_opts) do
      send_packet(
        Conn.connecting({transport, transport_opts}, endpoint, handle, packet, conn_options),
        packet
      )
    end
  end

  def data_received(%Conn{} = conn, message) do
    with {:ok, conn, packets} <- decode_data(conn, message),
         {:ok, conn} <-
           Conn.handle_packets_from_server(conn, packets) do
      {:ok, conn, packets}
    end
  end

  def disconnect(%Conn{} = conn, reason_code \\ :normal_disconnection) do
    packet = PacketBuilder.Disconnect.new(reason_code)

    with {:ok, conn} <- send_packet(conn, packet),
         :ok <- conn.transport.close(conn.handle) do
      Conn.disconnected(conn)
    end
  end

  def disconnect!(%Conn{} = conn) do
    with :ok <- conn.transport.close(conn.handle) do
      Conn.disconnected(conn)
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
      {topic_with_alias, conn} = Conn.topic_alias(conn, topic)

      packet =
        PacketBuilder.Publish.new(packet_identifier, topic_with_alias, payload, options)

      send_packet(conn, packet)
    end
  end

  def read_next_packet(%Conn{} = conn) do
    with {:ok, handle, packet, buffer} <- do_read_next_packet(conn, conn.read_buffer),
         {:ok, conn} <-
           Conn.handle_packet_from_server(Conn.update_handle(conn, handle), packet, buffer) do
      {:ok, packet, conn}
    end
  end

  def reconnect(%Conn{state: :disconnected} = conn) do
    connect_packet = PacketBuilder.Connect.with_clean_start(conn.connect_packet, false)

    Logger.info("endpoint=#{inspect(conn.endpoint)}, action=reconnect")

    with {:ok, handle} <- conn.transport.connect(conn.endpoint, conn.transport_opts),
         {:ok, conn} <- send_packet(Conn.reconnecting(conn, handle), connect_packet) do
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

  def send_packet(%Conn{} = conn, packet) do
    with {:ok, handle} <- conn.transport.send(conn.handle, Packet.encode!(packet)) do
      Logger.debug("event=packet_sent, packet=#{inspect(packet)}")
      {:ok, Conn.packet_sent(conn, handle, packet)}
    end
  end

  def set_mode(%Conn{} = conn, mode) when mode in [:active, :passive] do
    with {:ok, handle} <- conn.transport.set_mode(conn.handle, mode) do
      {:ok, Conn.update_handle(conn, handle)}
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

  defp do_read_next_packet(conn, buffer) do
    if byte_size(buffer) > 0 do
      case PacketDecoder.decode(buffer) do
        {:ok, packet, buffer} -> {:ok, conn.handle, packet, buffer}
        {:error, :incomplete_packet} -> do_read_next_packet_from_socket(conn, buffer)
      end
    else
      do_read_next_packet_from_socket(conn, buffer)
    end
  end

  defp do_read_next_packet_from_socket(conn, buffer) do
    with {:ok, handle, data} <- conn.transport.recv(conn.handle, 0, @default_read_timeout_ms) do
      Logger.debug(
        "handle=#{inspect(conn.handle)}, action=read, size=#{byte_size(data)}, data=#{Base.encode16(data)}"
      )

      buffer = buffer <> data

      case PacketDecoder.decode(buffer) do
        {:ok, packet, buffer} ->
          {:ok, handle, packet, buffer}

        {:error, :incomplete_packet} ->
          do_read_next_packet_from_socket(Conn.update_handle(conn, handle), buffer)

        other_error ->
          other_error
      end
    end
  end

  defp republish_unacknowledged_messages(conn, packet) do
    # When a Client reconnects with Clean Start set to 0 and a session is
    # present, both the Client and Server MUST resend any unacknowledged
    # PUBLISH packets (where QoS > 0) and PUBREL packets using their original
    # Packet Identifiers. This is the only circumstance where a Client or
    # Server is REQUIRED to resend messages. Clients and Servers MUST NOT
    # resend messages at any other time [MQTT-4.4.0-1].

    conn.session
    |> Session.unacknowledged_packets()
    |> Enum.reduce_while(conn, fn packet, conn ->
      dup_packet =
        case packet do
          %Packet.Publish{} -> PacketBuilder.Publish.with_dup(packet, true)
          %Packet.Pubrel{} -> packet
        end

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

  defp decode_data(conn, message) do
    with {:ok, handle, data} <- conn.transport.data_received(conn.handle, message) do
      buffer = conn.read_buffer <> data
      decode_packets(Conn.update_buffer(conn, handle, buffer), buffer)
    end
  end

  defp decode_packets(_conn, _buffer, _packets \\ [])

  defp decode_packets(conn, <<>>, packets), do: {:ok, conn, Enum.reverse(packets)}

  defp decode_packets(conn, data, packets) do
    case PacketDecoder.decode(data) do
      {:ok, packet, buffer} ->
        decode_packets(Conn.update_buffer(conn, buffer), buffer, [packet | packets])

      {:error, :incomplete_packet} ->
        {:ok, conn, Enum.reverse(packets)}

      other_error ->
        other_error
    end
  end
end
