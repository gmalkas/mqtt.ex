defmodule MQTT.Packet.Pingreq do
  @control_packet_type 12
  @fixed_header_flags 0

  defstruct []

  def encode!(%__MODULE__{}) do
    <<@control_packet_type::4, @fixed_header_flags::4, 0::8>>
  end
end
