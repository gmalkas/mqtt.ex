defmodule MQTT.ClientConn do
  alias MQTT.{Error, Packet}

  @max_packet_identifier 0xFFFF

  defstruct [
    :client_id,
    :connack_properties,
    :keep_alive,
    :last_packet_sent_at,
    :host,
    :packet_identifiers,
    :port,
    :read_buffer,
    :socket,
    :state,
    :transport
  ]

  def connecting(transport, host, port, socket, %Packet.Connect{} = packet) do
    %__MODULE__{
      client_id: packet.payload.client_id,
      host: host,
      keep_alive: packet.keep_alive,
      packet_identifiers: MapSet.new(),
      port: port,
      read_buffer: "",
      socket: socket,
      state: :connecting,
      transport: transport
    }
  end

  def disconnect(%__MODULE__{} = conn) do
    {:ok, %__MODULE__{conn | state: :disconnected}}
  end

  def handle_packet_from_server(%__MODULE__{} = conn, packet, buffer) do
    do_handle_packet_from_server(%__MODULE__{conn | read_buffer: buffer}, packet)
  end

  def next_packet_identifier(%__MODULE__{} = conn) do
    identifier = :rand.uniform(@max_packet_identifier)

    if !MapSet.member?(conn.packet_identifiers, identifier) do
      {identifier,
       %__MODULE__{conn | packet_identifiers: MapSet.put(conn.packet_identifiers, identifier)}}
    else
      next_packet_identifier(conn)
    end
  end

  def packet_sent(%__MODULE__{} = conn) do
    %__MODULE__{conn | last_packet_sent_at: monotonic_time()}
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
    if MapSet.member?(conn.packet_identifiers, packet.packet_identifier) do
      {:ok,
       %__MODULE__{
         conn
         | packet_identifiers: MapSet.delete(conn.packet_identifiers, packet.packet_identifier)
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Unsuback{} = packet) do
    if MapSet.member?(conn.packet_identifiers, packet.packet_identifier) do
      {:ok,
       %__MODULE__{
         conn
         | packet_identifiers: MapSet.delete(conn.packet_identifiers, packet.packet_identifier)
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
  end

  defp do_handle_packet_from_server(%__MODULE__{} = conn, %Packet.Puback{} = packet) do
    if MapSet.member?(conn.packet_identifiers, packet.packet_identifier) do
      {:ok,
       %__MODULE__{
         conn
         | packet_identifiers: MapSet.delete(conn.packet_identifiers, packet.packet_identifier)
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
  end

  defp monotonic_time, do: :erlang.monotonic_time(:millisecond)
end
