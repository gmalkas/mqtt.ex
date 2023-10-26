defmodule MQTT.PacketBuilder.Disconnect do
  alias MQTT.Packet.Disconnect

  def new(reason_code) do
    %Disconnect{
      reason_code: reason_code,
      properties: %Disconnect.Properties{}
    }
  end
end
