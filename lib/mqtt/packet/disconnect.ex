defmodule MQTT.Packet.Disconnect do
  alias MQTT.PacketEncoder

  @control_packet_type 14
  @fixed_header_flags 0

  defstruct [:reason_code, :properties]

  def encode!(%__MODULE__{} = packet) do
    reason_code = PacketEncoder.encode_reason_code(packet.reason_code)
    properties = PacketEncoder.encode_properties(packet.properties)

    variable_header =
      reason_code <> properties

    remaining_length = byte_size(variable_header)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header
  end
end
