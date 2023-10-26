defmodule MQTT.PacketBuilder.Connect do
  alias MQTT.Packet.Connect

  @default_protocol_name "MQTT"
  @default_protocol_version 5
  @default_will_qos 0
  @default_will_retain false
  @default_will_properties %Connect.Payload.WillProperties{}

  def new(options \\ []) do
    client_id = Keyword.get(options, :client_id) || ""
    keep_alive = Keyword.get(options, :keep_alive, 0)

    %Connect{
      protocol_name: @default_protocol_name,
      protocol_version: @default_protocol_version,
      keep_alive: keep_alive,
      properties: %Connect.Properties{},
      flags: %Connect.Flags{},
      payload: %Connect.Payload{client_id: client_id}
    }
  end

  def with_clean_start(%Connect{} = packet, value) when is_boolean(value) do
    %Connect{
      packet
      | flags: %Connect.Flags{packet.flags | clean_start?: value}
    }
  end

  def with_password(%Connect{} = packet, password) when is_binary(password) do
    %Connect{
      packet
      | flags: %Connect.Flags{packet.flags | password?: true},
        payload: %Connect.Payload{packet.payload | password: password}
    }
  end

  def with_user_name(%Connect{} = packet, user_name) when is_binary(user_name) do
    %Connect{
      packet
      | flags: %Connect.Flags{packet.flags | user_name?: true},
        payload: %Connect.Payload{packet.payload | user_name: user_name}
    }
  end

  def with_will_message(%Connect{} = packet, will_topic, will_payload, will_options \\ [])
      when is_binary(will_topic) and is_binary(will_payload) do
    will_qos = Keyword.get(will_options, :qos, @default_will_qos)
    will_retain? = Keyword.get(will_options, :retain?, @default_will_retain)
    will_properties = Keyword.get(will_options, :properties, @default_will_properties)

    %Connect{
      packet
      | flags: %Connect.Flags{
          packet.flags
          | will?: true,
            will_qos: will_qos,
            will_retain?: will_retain?
        },
        payload: %Connect.Payload{
          packet.payload
          | will_properties: will_properties,
            will_topic: will_topic,
            will_payload: will_payload
        }
    }
  end
end
