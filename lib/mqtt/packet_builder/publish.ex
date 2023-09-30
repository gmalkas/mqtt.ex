defmodule MQTT.PacketBuilder.Publish do
  alias MQTT.Packet.Publish

  def new(packet_identifier, topic_name, payload, options)
      when is_binary(topic_name) and is_binary(payload) do
    qos = Keyword.get(options, :qos, 0)
    retain? = Keyword.get(options, :retain?, false)

    %Publish{
      packet_identifier: packet_identifier,
      properties: %{},
      flags: %Publish.Flags{qos: qos, retain?: retain?},
      payload: %Publish.Payload{data: payload},
      topic_name: topic_name
    }
  end
end
