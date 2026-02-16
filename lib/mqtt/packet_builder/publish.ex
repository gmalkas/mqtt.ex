defmodule MQTT.PacketBuilder.Publish do
  alias MQTT.{Packet, Packet.Publish}

  @no_topic_alias 0

  def new(topic_name, payload, options, properties \\ [])
      when is_binary(topic_name) and is_binary(payload) do
    new(
      Packet.random_packet_identifier(),
      {@no_topic_alias, topic_name},
      payload,
      options,
      properties
    )
  end

  def new(packet_identifier, {topic_alias, topic_name}, payload, options, properties)
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
      properties:
        struct!(Publish.Properties, Keyword.merge(properties, topic_alias: topic_alias)),
      flags: %Publish.Flags{qos: qos, retain?: retain?},
      payload: %Publish.Payload{data: payload},
      topic_name: topic_name
    }
  end

  def with_correlation_data(%Publish{properties: %Publish.Properties{} = props} = packet, data) do
    %Publish{packet | properties: %Publish.Properties{props | correlation_data: data}}
  end

  def with_dup(%Publish{flags: %Publish.Flags{} = flags} = packet, value)
      when is_boolean(value) do
    %Publish{packet | flags: %Publish.Flags{flags | dup?: value}}
  end

  def with_response_topic(%Publish{properties: %Publish.Properties{} = props} = packet, topic) do
    %Publish{packet | properties: %Publish.Properties{props | response_topic: topic}}
  end
end
