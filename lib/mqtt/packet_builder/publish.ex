defmodule MQTT.PacketBuilder.Publish do
  alias MQTT.Packet.Publish

  @no_topic_alias 0

  def new(packet_identifier, {topic_alias, topic_name}, payload, options)
      when is_integer(topic_alias) and is_binary(topic_name) and is_binary(payload) do
    qos = Keyword.get(options, :qos, 0)
    retain? = Keyword.get(options, :retain?, false)

    topic_alias =
      if topic_alias == @no_topic_alias do
        nil
      else
        topic_alias
      end

    %Publish{
      packet_identifier: packet_identifier,
      properties: %Publish.Properties{topic_alias: topic_alias},
      flags: %Publish.Flags{qos: qos, retain?: retain?},
      payload: %Publish.Payload{data: payload},
      topic_name: topic_name
    }
  end

  def with_dup(%Publish{} = packet, value) when is_boolean(value) do
    %Publish{packet | flags: %Publish.Flags{packet.flags | dup?: value}}
  end
end
