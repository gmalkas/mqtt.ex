defmodule MQTT.PacketBuilder.Disconnect do
  alias MQTT.Packet.Disconnect

  def new(reason_code) do
    %Disconnect{
      reason_code: reason_code,
      properties: %Disconnect.Properties{}
    }
  end

  def with_reason_string(%Disconnect{} = packet, reason_string) when is_binary(reason_string) do
    %Disconnect{
      packet
      | properties: %Disconnect.Properties{packet.properties | reason_string: reason_string}
    }
  end
end
