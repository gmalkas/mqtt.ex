defmodule MQTT.ClientConn do
  alias MQTT.{Error, Packet}

  @max_packet_identifier 0xFFFF

  defstruct [:ip_address, :port, :client_id, :socket, :state, :read_buffer, :packet_identifiers]

  def connecting(ip_address, port, client_id, socket) when is_port(socket) do
    %__MODULE__{
      client_id: client_id,
      ip_address: ip_address,
      packet_identifiers: MapSet.new(),
      port: port,
      read_buffer: "",
      socket: socket,
      state: :connecting
    }
  end

  def disconnect(%__MODULE__{} = conn) do
    {:ok, %__MODULE__{conn | state: :disconnected}}
  end

  def handle_packet_from_server(%__MODULE__{} = conn, %Packet.Connack{} = _packet, buffer) do
    {:ok, %__MODULE__{conn | state: :connected, read_buffer: buffer}}
  end

  def handle_packet_from_server(%__MODULE__{} = conn, %Packet.Publish{} = _packet, buffer) do
    {:ok, %__MODULE__{conn | read_buffer: buffer}}
  end

  def handle_packet_from_server(%__MODULE__{} = conn, %Packet.Pingresp{} = _packet, buffer) do
    {:ok, %__MODULE__{conn | read_buffer: buffer}}
  end

  def handle_packet_from_server(%__MODULE__{} = conn, %Packet.Suback{} = packet, buffer) do
    if MapSet.member?(conn.packet_identifiers, packet.packet_identifier) do
      {:ok,
       %__MODULE__{
         conn
         | packet_identifiers: MapSet.delete(conn.packet_identifiers, packet.packet_identifier),
           read_buffer: buffer
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
  end

  def handle_packet_from_server(%__MODULE__{} = conn, %Packet.Puback{} = packet, buffer) do
    if MapSet.member?(conn.packet_identifiers, packet.packet_identifier) do
      {:ok,
       %__MODULE__{
         conn
         | packet_identifiers: MapSet.delete(conn.packet_identifiers, packet.packet_identifier),
           read_buffer: buffer
       }}
    else
      {:error, Error.packet_identifier_not_found(packet.packet_identifier)}
    end
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
end
