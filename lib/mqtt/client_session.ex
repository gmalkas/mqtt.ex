defmodule MQTT.ClientSession do
  alias MQTT.Packet

  @max_packet_identifier 0xFFFF

  defstruct unacknowledged_packets: Map.new(),
            unacknowledged_packet_identifiers: [],
            used_packet_identifiers: MapSet.new()

  def new do
    %__MODULE__{}
  end

  def allocate_packet_identifier(%__MODULE__{} = session) do
    identifier = :rand.uniform(@max_packet_identifier)

    if !MapSet.member?(session.used_packet_identifiers, identifier) do
      {identifier,
       %__MODULE__{
         session
         | used_packet_identifiers: MapSet.put(session.used_packet_identifiers, identifier)
       }}
    else
      allocate_packet_identifier(session)
    end
  end

  def free_packet_identifier(%__MODULE__{} = session, packet_identifier) do
    %__MODULE__{
      session
      | unacknowledged_packets: Map.delete(session.unacknowledged_packets, packet_identifier),
        unacknowledged_packet_identifiers:
          List.delete(session.unacknowledged_packet_identifiers, packet_identifier),
        used_packet_identifiers: MapSet.delete(session.used_packet_identifiers, packet_identifier)
    }
  end

  def handle_packet_from_client(%__MODULE__{} = session, %Packet.Publish{} = packet) do
    if packet.flags.qos == 1 &&
         !Map.has_key?(session.unacknowledged_packets, packet.packet_identifier) do
      %__MODULE__{
        session
        | unacknowledged_packets:
            Map.put(session.unacknowledged_packets, packet.packet_identifier, packet),
          unacknowledged_packet_identifiers: [
            packet.packet_identifier | session.unacknowledged_packet_identifiers
          ]
      }
    else
      session
    end
  end

  def handle_packet_from_client(%__MODULE__{} = session, _packet) do
    session
  end

  def handle_packet_from_server(%__MODULE__{} = session, %Packet.Puback{} = packet) do
    %__MODULE__{
      session
      | unacknowledged_packets:
          Map.delete(session.unacknowledged_packets, packet.packet_identifier),
        unacknowledged_packet_identifiers:
          List.delete(session.unacknowledged_packet_identifiers, packet.packet_identifier)
    }
    |> free_packet_identifier(packet.packet_identifier)
  end

  def handle_packet_from_server(%__MODULE__{} = session, packet) do
    free_packet_identifier(session, packet.packet_identifier)
  end

  def has_packet_identifier?(%__MODULE__{} = session, packet_identifier) do
    MapSet.member?(session.used_packet_identifiers, packet_identifier)
  end

  def unacknowledged_packets(%__MODULE__{} = session) do
    session.unacknowledged_packet_identifiers
    |> Enum.reverse()
    |> Enum.map(&Map.fetch!(session.unacknowledged_packets, &1))
  end

  def unacknowledged_message_count(%__MODULE__{} = session),
    do: map_size(session.unacknowledged_packets)
end
