defmodule MQTT.PacketBuilder.Suback do
  alias MQTT.Packet.Suback

  def new(packet_identifier, reason_codes)
      when is_integer(packet_identifier) and is_list(reason_codes) do
    %Suback{
      packet_identifier: packet_identifier,
      properties: %Suback.Properties{},
      payload: %Suback.Payload{reason_codes: reason_codes}
    }
  end
end
