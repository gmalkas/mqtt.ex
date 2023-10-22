defmodule MQTT.PacketBuilder.Connack do
  alias MQTT.Packet.Connack

  def new(options \\ []) do
    %Connack{
      properties: %Connack.Properties{},
      reason_code: Keyword.get(options, :reason_code, :success),
      flags: %Connack.Flags{}
    }
  end
end
