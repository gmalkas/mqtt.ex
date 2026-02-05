defmodule MQTT.Client do
  require Logger

  alias MQTT.ClientConn, as: Conn
  alias MQTT.ClientSession, as: Session
  alias MQTT.{Packet, PacketBuilder, PacketDecoder, Transport, TransportError}

  @default_read_timeout_ms 500

  def auth(%Conn{} = conn, reason_code, authentication_method, authentication_data \\ nil) do
    packet = PacketBuilder.Auth.new(reason_code, authentication_method, authentication_data)

    send_packet(conn, packet)
  end

  def connect(endpoint, options \\ []) do
    transport = Keyword.get(options, :transport, Transport.TCP)
    transport_opts = Keyword.get(options, :transport_opts, [])

    conn_options = Keyword.take(options, [:connect_timeout, :reconnect_strategy, :timeout])

    client_id = Keyword.get(options, :client_id)
    user_name = Keyword.get(options, :user_name)
    password = Keyword.get(options, :password)
    enhanced_authentication = Keyword.get(options, :enhanced_authentication)
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

    packet =
      case enhanced_authentication do
        nil ->
          packet

        {authentication_method, authentication_data} ->
          PacketBuilder.Connect.with_enhanced_authentication(
            packet,
            authentication_method,
            authentication_data
          )
      end

    Logger.info("endpoint=#{inspect(endpoint)}, action=connect")

    conn = Conn.new({transport, transport_opts}, endpoint, conn_options)

    with {:ok, handle} <- transport.connect(endpoint, transport_opts) do
      send_packet(
        Conn.connecting(conn, handle, packet),
        packet
      )
    else
      {:error, error} ->
        {:error, error, Conn.disconnected(conn)}
    end
  end

  def data_received(%Conn{} = conn, message) do
    case decode_data(conn, message) do
      {:ok, conn, packets} ->
        with {:ok, conn} <- Conn.handle_packets_from_server(conn, packets),
             {:ok, conn} <- maybe_republish_unacknowledged_messages(conn, packets) do
          {:ok, conn, packets}
        end

      {:ok, :transport_closed} ->
        {:ok, conn} = Conn.disconnected(conn, reconnect?: true)

        {:ok, conn, :closed}
    end
  end

  def disconnect(%Conn{} = conn, reason_code, reason_string \\ nil) do
    # The CONNACK and DISCONNECT packets allow a Reason Code of 0x80 or greater
    # to indicate that the Network Connection will be closed. If a Reason Code
    # of 0x80 or greater is specified, then the Network Connection MUST be
    # closed whether or not the CONNACK or DISCONNECT is sent [MQTT-4.13.2-1]

    # We close the socket regardless of the reason code as there isn't a reason
    # to keep the socket open after sending DISCONNECT.

    packet = PacketBuilder.Disconnect.new(reason_code)

    packet =
      if !is_nil(reason_string) do
        PacketBuilder.Disconnect.with_reason_string(packet, reason_string)
      else
        packet
      end

    with {:ok, _, conn} <- send_packet(conn, packet),
         :ok <- conn.transport.close(conn.handle) do
      Conn.disconnected(conn, reconnect?: false)
    end
  end

  def disconnect(%Conn{} = conn) do
    with :ok <- conn.transport.close(conn.handle) do
      Conn.disconnected(conn, reconnect?: false)
    end
  end

  def ping(%Conn{} = conn) do
    packet = PacketBuilder.Pingreq.new()

    send_packet(conn, packet)
  end

  def publish(%Conn{} = conn, topic, payload, options \\ []) do
    qos = Keyword.get(options, :qos, 0)
    retain? = Keyword.get(options, :retain?, false)
    properties = Keyword.get(options, :properties, [])

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
        PacketBuilder.Publish.new(
          packet_identifier,
          topic_with_alias,
          payload,
          options,
          properties
        )

      send_packet(conn, packet)
    end
  end

  def read_next_packet(%Conn{} = conn) do
    with {:ok, handle, packet, buffer} <- do_read_next_packet(conn, conn.read_buffer),
         {:ok, conn} <-
           Conn.handle_packet_from_server(Conn.update_handle(conn, handle), packet, buffer),
         {:ok, conn} <- maybe_republish_unacknowledged_messages(conn, [packet]) do
      {:ok, packet, conn}
    end
  end

  def reconnect(%Conn{state: :disconnected} = conn) do
    connect_packet = PacketBuilder.Connect.with_clean_start(conn.connect_packet, false)

    Logger.info("endpoint=#{inspect(conn.endpoint)}, action=reconnect")

    with {:ok, handle} <- conn.transport.connect(conn.endpoint, conn.transport_opts) do
      send_packet(Conn.reconnecting(conn, handle), connect_packet)
    end
    |> case do
      {:error, %TransportError{} = error} ->
        {:error, error, Conn.reconnecting_failed(conn)}

      other ->
        other
    end
  end

  def send_packet(%Conn{} = conn, packet) do
    encoded_packet = Packet.encode!(packet)

    if !Conn.oversized?(conn, encoded_packet) do
      with {:ok, handle} <- conn.transport.send(conn.handle, encoded_packet) do
        Logger.debug("event=packet_sent, packet=#{inspect(packet)}")
        {:ok, packet, Conn.packet_sent(conn, handle, packet)}
      end
    else
      {:error, :packet_too_large}
    end
  end

  def set_mode(%Conn{} = conn, mode) when mode in [:active, :passive] do
    case conn.transport.set_mode(conn.handle, mode) do
      {:ok, handle} ->
        {:ok, Conn.update_handle(conn, handle)}

      {:error, error} ->
        {:error, error, conn}
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

  defp maybe_republish_unacknowledged_messages(conn, packets) do
    packets
    |> Enum.find(fn
      %Packet.Connack{} -> true
      _ -> false
    end)
    |> case do
      nil ->
        {:ok, conn}

      packet ->
        if packet.flags.session_present? do
          republish_unacknowledged_messages(conn)
        else
          {:ok, Conn.destroy_session(conn)}
        end
    end
  end

  defp republish_unacknowledged_messages(conn) do
    # When a Client reconnects with Clean Start set to 0 and a session is
    # present, both the Client and Server MUST resend any unacknowledged
    # PUBLISH packets (where QoS > 0) and PUBREL packets using their original
    # Packet Identifiers. This is the only circumstance where a Client or
    # Server is REQUIRED to resend messages. Clients and Servers MUST NOT
    # resend messages at any other time [MQTT-4.4.0-1].

    conn.session
    |> Session.unacknowledged_packets()
    |> Enum.reduce_while({:ok, conn}, fn packet, {:ok, conn} ->
      dup_packet =
        case packet do
          %Packet.Publish{} -> PacketBuilder.Publish.with_dup(packet, true)
          %Packet.Pubrel{} -> packet
        end

      case send_packet(conn, dup_packet) do
        {:ok, _, conn} -> {:cont, {:ok, conn}}
        error -> {:halt, error}
      end
    end)
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
