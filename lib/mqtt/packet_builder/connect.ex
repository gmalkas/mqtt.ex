defmodule MQTT.PacketBuilder.Connect do
  alias MQTT.Packet.Connect

  @default_protocol_name "MQTT"
  @default_protocol_version 5

  def new(client_id) when is_binary(client_id) do
    %Connect{
      protocol_name: @default_protocol_name,
      protocol_version: @default_protocol_version,
      keep_alive: 0,
      properties: %{},
      flags: %Connect.Flags{},
      payload: %Connect.Payload{client_id: client_id}
    }
  end
end
