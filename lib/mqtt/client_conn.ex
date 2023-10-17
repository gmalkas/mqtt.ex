defmodule MQTT.ClientConn do
  alias MQTT.{Error, Packet}
  alias MQTT.ClientSession, as: Session

  @initial_topic_alias 1
  @no_topic_alias 0

  defstruct [
    :client_id,
    :connect_packet,
    :connack_properties,
    :keep_alive,
    :last_packet_sent_at,
    :endpoint,
    :next_topic_alias,
    :read_buffer,
    :session,
    :handle,
    :state,
    :topic_aliases,
    :transport,
    :transport_opts
  ]

  def connecting({transport, transport_opts}, endpoint, handle, %Packet.Connect{} = packet) do
    %__MODULE__{
      client_id: packet.payload.client_id,
      connect_packet: packet,
      endpoint: endpoint,
      keep_alive: packet.keep_alive,
      next_topic_alias: @initial_topic_alias,
      read_buffer: "",
      session: Session.new(),
      handle: handle,
      state: :connecting,
      topic_aliases: %{},
      transport: transport,
      transport_opts: transport_opts
    }
  end

  def destroy_session(%__MODULE__{} = conn) do
    %__MODULE__{conn | session: Session.new()}
  end

  def disconnect(%__MODULE__{} = conn) do
    {:ok, %__MODULE__{conn | state: :disconnected}}
  end

  def fetch_topic_alias(%__MODULE__{} = conn, topic) when is_binary(topic) do
    Map.fetch(conn.topic_aliases, topic)
  end

  def handle_packet_from_server(%__MODULE__{} = conn, packet, buffer) do
    do_handle_packet_from_server(%__MODULE__{conn | read_buffer: buffer}, packet)
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

  def update_handle(%__MODULE__{} = conn, handle) do
    %__MODULE__{conn | handle: handle}
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Connack{} = packet) do
    client_id =
      if !is_nil(packet.properties.assigned_client_identifier) do
        packet.properties.assigned_client_identifier
      else
        conn.client_id
      end

    {:ok,
     %__MODULE__{
       conn
       | state: :connected,
         client_id: client_id,
         connack_properties: packet.properties
     }}
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Publish{} = _packet) do
    {:ok, conn}
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Pingresp{} = _packet) do
    {:ok, conn}
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
    map_size(conn.topic_aliases) < conn.connack_properties.topic_alias_maximum
  end
end
