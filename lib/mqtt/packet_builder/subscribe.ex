defmodule MQTT.PacketBuilder.Subscribe do
  alias MQTT.Packet.Subscribe

  def new(packet_identifier, topic_filters)
      when is_integer(packet_identifier) and is_list(topic_filters) do
    if length(topic_filters) == 0 do
      raise ArgumentError,
            "at least one topic filter is required to build a valid Subscribe packet"
    end

    topic_filters =
      topic_filters
      |> Enum.map(fn
        topic_filter when is_binary(topic_filter) ->
          {topic_filter, Subscribe.SubscriptionOptions.from_params([])}

        {topic_filter, options} when is_binary(topic_filter) ->
          {topic_filter, Subscribe.SubscriptionOptions.from_params(options)}
      end)

    %Subscribe{
      packet_identifier: packet_identifier,
      properties: %{},
      payload: %Subscribe.Payload{topic_filters: topic_filters}
    }
  end
end
