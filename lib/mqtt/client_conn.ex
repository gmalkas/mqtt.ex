defmodule MQTT.ClientConn do
  alias MQTT.{Client.ReconnectStrategy, Error, Packet}
  alias MQTT.ClientSession, as: Session

  @initial_topic_alias 1
  @no_topic_alias 0
  @default_timeout_ms 30_000
  @default_reconnect_strategy ReconnectStrategy.ConstantBackoff.new(1)

  defstruct [
    :client_id,
    :connect_packet,
    :connack_properties,
    :endpoint,
    :handle,
    :keep_alive,
    :keep_alive_timer,
    :last_packet_sent_at,
    :next_topic_alias,
    :ping_timer,
    :read_buffer,
    :reconnect_retry_count,
    :reconnect_strategy,
    :reconnect_timer,
    :session,
    :state,
    :timeout,
    :topic_aliases,
    :transport,
    :transport_opts
  ]

  def connecting(
        {transport, transport_opts},
        endpoint,
        handle,
        %Packet.Connect{} = packet,
        options \\ []
      ) do
    %__MODULE__{
      client_id: packet.payload.client_id,
      connect_packet: packet,
      endpoint: endpoint,
      handle: handle,
      keep_alive: packet.keep_alive,
      next_topic_alias: @initial_topic_alias,
      read_buffer: "",
      reconnect_retry_count: 0,
      reconnect_strategy: Keyword.get(options, :reconnect_strategy, @default_reconnect_strategy),
      timeout: Keyword.get(options, :timeout, @default_timeout_ms),
      session: Session.new(),
      state: :connecting,
      topic_aliases: %{},
      transport: transport,
      transport_opts: transport_opts
    }
  end

  def destroy_session(%__MODULE__{} = conn) do
    %__MODULE__{conn | session: Session.new()}
  end

  def disconnected(%__MODULE__{} = conn, should_reconnect? \\ false) do
    cancel_timer!(conn.keep_alive_timer)
    cancel_timer!(conn.ping_timer)

    reconnect_timer =
      if should_reconnect? do
        set_reconnect_timer(conn)
      else
        nil
      end

    {:ok,
     %__MODULE__{
       conn
       | handle: nil,
         keep_alive_timer: nil,
         ping_timer: nil,
         reconnect_timer: reconnect_timer,
         state: :disconnected
     }}
  end

  def fetch_topic_alias(%__MODULE__{} = conn, topic) when is_binary(topic) do
    Map.fetch(conn.topic_aliases, topic)
  end

  def handle_packet_from_server(%__MODULE__{} = conn, packet) do
    do_handle_packet_from_server(conn, packet)
  end

  def handle_packet_from_server(%__MODULE__{} = conn, packet, buffer) when is_binary(buffer) do
    do_handle_packet_from_server(%__MODULE__{conn | read_buffer: buffer}, packet)
  end

  def handle_packets_from_server(%__MODULE__{} = conn, packets) when is_list(packets) do
    Enum.reduce_while(packets, {:ok, conn}, fn packet, {:ok, conn} ->
      case do_handle_packet_from_server(conn, packet) do
        {:ok, next_conn} -> {:cont, {:ok, next_conn}}
        error -> {:halt, error}
      end
    end)
  end

  def has_keep_alive?(%__MODULE__{} = conn) do
    !is_nil(conn.keep_alive) && conn.keep_alive > 0
  end

  def next_packet_identifier(%__MODULE__{} = conn) do
    {packet_identifier, session} = Session.allocate_packet_identifier(conn.session)

    {packet_identifier, %__MODULE__{conn | session: session}}
  end

  def topic_alias(%__MODULE__{} = conn, topic) do
    if Map.has_key?(conn.topic_aliases, topic) do
      {{Map.fetch!(conn.topic_aliases, topic), ""}, conn}
    else
      if can_allocate_topic_alias?(conn) do
        {{conn.next_topic_alias, topic},
         %__MODULE__{
           conn
           | next_topic_alias: conn.next_topic_alias + 1,
             topic_aliases: Map.put(conn.topic_aliases, topic, conn.next_topic_alias)
         }}
      else
        {{@no_topic_alias, topic}, conn}
      end
    end
  end

  def packet_sent(%__MODULE__{} = conn, handle, packet) do
    conn =
      conn
      |> reset_keep_alive_timer()
      |> maybe_reset_ping_timer(packet)

    %__MODULE__{
      conn
      | handle: handle,
        last_packet_sent_at: monotonic_time(),
        session: Session.handle_packet_from_client(conn.session, packet)
    }
  end

  def reconnecting(%__MODULE__{state: :disconnected} = conn, handle) do
    %__MODULE__{
      conn
      | handle: handle,
        state: :reconnecting,
        topic_aliases: %{},
        next_topic_alias: @initial_topic_alias
    }
  end

  def reconnecting_failed(%__MODULE__{state: state} = conn)
      when state in [:reconnecting, :disconnected] do
    %__MODULE__{
      conn
      | handle: nil,
        reconnect_retry_count: conn.reconnect_retry_count + 1,
        reconnect_timer: set_reconnect_timer(conn),
        state: :disconnected
    }
  end

  def reset_keep_alive_timer(%__MODULE__{} = conn) do
    cancel_timer!(conn.keep_alive_timer)

    timer_ref =
      if has_keep_alive?(conn) do
        {:ok, ref} = :timer.send_after(:timer.seconds(conn.keep_alive), self(), :keep_alive)

        ref
      else
        nil
      end

    %__MODULE__{conn | keep_alive_timer: timer_ref}
  end

  def retain_available?(%__MODULE__{} = conn) do
    conn.connack_properties.retain_available
  end

  def set_topic_alias_maximum(%__MODULE__{} = conn, topic_alias_maximum)
      when is_integer(topic_alias_maximum) do
    %__MODULE__{
      conn
      | connack_properties: %Packet.Connack.Properties{
          conn.connack_properties
          | topic_alias_maximum: topic_alias_maximum
        }
    }
  end

  def should_ping?(%__MODULE__{keep_alive: 0}), do: false

  def should_ping?(%__MODULE__{} = conn) do
    is_nil(conn.last_packet_sent_at) ||
      monotonic_time() - conn.last_packet_sent_at > conn.keep_alive
  end

  def update_buffer(%__MODULE__{} = conn, buffer) when is_binary(buffer) do
    %__MODULE__{conn | read_buffer: buffer}
  end

  def update_buffer(%__MODULE__{} = conn, handle, buffer) when is_binary(buffer) do
    %__MODULE__{conn | read_buffer: buffer, handle: handle}
  end

  def update_handle(%__MODULE__{} = conn, handle) do
    %__MODULE__{conn | handle: handle}
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Auth{} = _packet) do
    {:ok, conn}
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Connack{} = packet) do
    # If the Client connects using a zero length Client Identifier, the Server
    # MUST respond with a CONNACK containing an Assigned Client Identifier. The
    # Assigned Client Identifier MUST be a new Client Identifier not used by
    # any other Session currently in the Server [MQTT-3.2.2-16].

    client_id =
      if !is_nil(packet.properties.assigned_client_identifier) do
        packet.properties.assigned_client_identifier
      else
        conn.client_id
      end

    # If the Server returns a Server Keep Alive on the CONNACK packet, the
    # Client MUST use that value instead of the value it sent as the Keep Alive
    # [MQTT-3.1.2-21].
    keep_alive =
      if !is_nil(packet.properties.server_keep_alive) do
        packet.properties.server_keep_alive
      else
        conn.keep_alive
      end

    {:ok,
     reset_keep_alive_timer(%__MODULE__{
       conn
       | state: :connected,
         client_id: client_id,
         connack_properties: packet.properties,
         keep_alive: keep_alive,
         reconnect_retry_count: 0
     })}
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Publish{} = _packet) do
    {:ok, conn}
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Pingresp{} = _packet) do
    cancel_timer!(conn.ping_timer)

    {:ok, %__MODULE__{conn | ping_timer: nil}}
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Suback{} = packet) do
    if Session.has_packet_identifier?(conn.session, packet.packet_identifier) do
      {:ok,
       %__MODULE__{
         conn
         | session: Session.handle_packet_from_server(conn.session, packet)
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Unsuback{} = packet) do
    if Session.has_packet_identifier?(conn.session, packet.packet_identifier) do
      {:ok,
       %__MODULE__{
         conn
         | session: Session.handle_packet_from_server(conn.session, packet)
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %module{} = packet)
       when module in [Packet.Puback, Packet.Pubrec, Packet.Pubcomp] do
    if Session.has_packet_identifier?(conn.session, packet.packet_identifier) do
      {:ok,
       %__MODULE__{
         conn
         | session: Session.handle_packet_from_server(conn.session, packet)
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
  end

  defp monotonic_time, do: :erlang.monotonic_time(:millisecond)

  defp can_allocate_topic_alias?(conn) do
    # Clients are allowed to send further MQTT Control Packets
    # immediately after sending a CONNECT packet; Clients need not wait for a
    # CONNACK packet to arrive from the Server. [MQTT-3.1.4]

    # If we have not received a CONNACK message yet, we simply assume that topic
    # aliases will be supported.
    is_nil(conn.connack_properties) ||
      map_size(conn.topic_aliases) < conn.connack_properties.topic_alias_maximum
  end

  defp maybe_reset_ping_timer(conn, %Packet.Pingreq{}) do
    cancel_timer!(conn.ping_timer)

    {:ok, timer_ref} = :timer.send_after(conn.timeout, self(), :ping_timeout)

    %__MODULE__{conn | ping_timer: timer_ref}
  end

  defp maybe_reset_ping_timer(conn, _), do: conn

  defp cancel_timer!(nil), do: :ok
  defp cancel_timer!(ref), do: {:ok, :cancel} = :timer.cancel(ref)

  defp set_reconnect_timer(conn) do
    delay_s =
      conn.reconnect_strategy.__struct__.delay(
        conn.reconnect_strategy,
        conn.reconnect_retry_count
      )

    {:ok, timer_ref} = :timer.send_after(:timer.seconds(delay_s), self(), :reconnect)

    timer_ref
  end
end
