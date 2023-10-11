defmodule MQTT.ClientConn do
  alias MQTT.{Error, Packet}
  alias MQTT.ClientSession, as: Session

  defstruct [
    :client_id,
    :connect_packet,
    :connack_properties,
    :keep_alive,
    :last_packet_sent_at,
    :host,
    :port,
    :read_buffer,
    :session,
    :socket,
    :state,
    :transport,
    :transport_opts
  ]

  def connecting({transport, transport_opts}, host, port, socket, %Packet.Connect{} = packet) do
    %__MODULE__{
      client_id: packet.payload.client_id,
      connect_packet: packet,
      host: host,
      keep_alive: packet.keep_alive,
      port: port,
      read_buffer: "",
      session: Session.new(),
      socket: socket,
      state: :connecting,
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

  def handle_packet_from_server(%__MODULE__{} = conn, packet, buffer) do
    do_handle_packet_from_server(%__MODULE__{conn | read_buffer: buffer}, packet)
  end

  def next_packet_identifier(%__MODULE__{} = conn) do
    {packet_identifier, session} = Session.allocate_packet_identifier(conn.session)

    {packet_identifier, %__MODULE__{conn | session: session}}
  end

  def packet_sent(%__MODULE__{} = conn, packet) do
    %__MODULE__{
      conn
      | last_packet_sent_at: monotonic_time(),
        session: Session.handle_packet_from_client(conn.session, packet)
    }
  end

  def reconnecting(%__MODULE__{state: :disconnected} = conn, socket) do
    %__MODULE__{conn | socket: socket, state: :reconnecting}
  end

  def retain_available?(%__MODULE__{} = conn) do
    conn.connack_properties.retain_available
  end

  def should_ping?(%__MODULE__{keep_alive: 0}), do: false

  def should_ping?(%__MODULE__{} = conn) do
    is_nil(conn.last_packet_sent_at) ||
      monotonic_time() - conn.last_packet_sent_at > conn.keep_alive
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
         | session: Session.free_packet_identifier(conn.session, packet.packet_identifier)
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
         | session: Session.free_packet_identifier(conn.session, packet.packet_identifier)
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Puback{} = packet) do
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
end
