defmodule MQTT.PacketBuilder.Pubrel do
  alias MQTT.Packet.Pubrel

  def new(packet_identifier, reason_code \\ :success) do
    %Pubrel{
      packet_identifier: packet_identifier,
      properties: %Pubrel.Properties{},
      reason_code: reason_code
    }
  end
end
