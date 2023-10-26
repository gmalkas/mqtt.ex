defmodule MQTT.PacketBuilder.Unsubscribe do
  alias MQTT.Packet.Unsubscribe

  def new(packet_identifier, topic_filters)
      when is_integer(packet_identifier) and is_list(topic_filters) do
    if length(topic_filters) == 0 do
      raise ArgumentError,
            "at least one topic filter is required to build a valid Unsubscribe packet"
    end

    %Unsubscribe{
      packet_identifier: packet_identifier,
      properties: %Unsubscribe.Properties{},
      payload: %Unsubscribe.Payload{topic_filters: topic_filters}
    }
  end
end
