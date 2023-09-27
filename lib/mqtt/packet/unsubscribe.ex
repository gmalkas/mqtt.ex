defmodule MQTT.Packet.Unsubscribe do
  alias MQTT.PacketEncoder

  @control_packet_type 10
  @fixed_header_flags 2

  defstruct [:packet_identifier, :properties, :payload]

  def encode!(%__MODULE__{} = packet) do
    packet_identifier = PacketEncoder.encode_two_byte_integer(packet.packet_identifier)
    properties = PacketEncoder.encode_properties(packet.properties)

    variable_header = packet_identifier <> properties

    payload = __MODULE__.Payload.encode!(packet.payload)

    remaining_length = byte_size(variable_header) + byte_size(payload)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header <> payload
  end
end

defmodule MQTT.Packet.Unsubscribe.Payload do
  alias MQTT.PacketEncoder

  defstruct [:topic_filters]

  def encode!(%__MODULE__{} = payload) do
    payload.topic_filters
    |> Enum.map(&PacketEncoder.encode_utf8_string/1)
    |> Enum.join(<<>>)
  end
end
