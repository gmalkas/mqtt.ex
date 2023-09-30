defmodule MQTT.Error do
  alias MQTT.ErrorContext

  defstruct [:reason_code_name, :context]

  def duplicated_property(property_name, value_count) do
    new(:protocol_error, ErrorContext.DuplicatedProperty.new(property_name, value_count))
  end

  def malformed_packet(reason \\ nil) do
    new(:malformed_packet, ErrorContext.MalformedPacket.new(reason))
  end

  def packet_identifier_not_found(packet_identifier) do
    new(
      :packet_identifier_not_found,
      ErrorContext.PacketIdentifierNotFound.new(packet_identifier)
    )
  end

  def new(reason_code_name, context) do
    %__MODULE__{reason_code_name: reason_code_name, context: context}
  end
end

defmodule MQTT.ErrorContext.DuplicatedProperty do
  @property_names MQTT.Packet.property_names()

  defstruct [:property_name, :value_count]

  def new(property_name, value_count)
      when property_name in @property_names do
    %__MODULE__{property_name: property_name, value_count: value_count}
  end
end

defmodule MQTT.ErrorContext.MalformedPacket do
  defstruct [:reason]

  def new(reason) when is_nil(reason) or is_binary(reason) do
    %__MODULE__{reason: reason}
  end
end

defmodule MQTT.ErrorContext.PacketIdentifierNotFound do
  defstruct [:packet_identifier]

  def new(packet_identifier) do
    %__MODULE__{packet_identifier: packet_identifier}
  end
end
