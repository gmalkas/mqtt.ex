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

  def with_user_name(%Connect{} = packet, user_name) when is_binary(user_name) do
    %Connect{
      packet
      | flags: %Connect.Flags{packet.flags | user_name?: true},
        payload: %Connect.Payload{packet.payload | user_name: user_name}
    }
  end

  def with_password(%Connect{} = packet, password) when is_binary(password) do
    %Connect{
      packet
      | flags: %Connect.Flags{packet.flags | password?: true},
        payload: %Connect.Payload{packet.payload | password: password}
    }
  end
end
