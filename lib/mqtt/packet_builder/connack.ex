defmodule MQTT.PacketBuilder.Connack do
  alias MQTT.Packet.Connack

  def new(reason_code \\ :success) do
    %Connack{
      properties: %Connack.Properties{},
      reason_code: reason_code,
      flags: %Connack.Flags{}
    }
  end

  def with_server_redirection(%Connack{} = packet, reason_code, server_reference \\ nil)
      when reason_code in [:server_moved, :use_another_server] do
    %Connack{
      packet
      | properties: %Connack.Properties{packet.properties | server_reference: server_reference},
        reason_code: reason_code
    }
  end
end
