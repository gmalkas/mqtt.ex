defmodule MQTT.Error do
  alias MQTT.ErrorContext

  defstruct [:reason_code_name, :context]

  def invalid_properties(property_name, reason) do
    new(:protocol_error, ErrorContext.InvalidProperties.new(property_name, reason))
  end

  def malformed_packet(reason \\ nil) do
    new(:malformed_packet, ErrorContext.MalformedPacket.new(reason))
  end

  def new(reason_code_name, context) do
    %__MODULE__{reason_code_name: reason_code_name, context: context}
  end
end

defmodule MQTT.ErrorContext.InvalidProperties do
  @property_names MQTT.Packet.property_names()

  defstruct [:property_name, :reason]

  def new(property_name, reason)
      when property_name in @property_names and is_binary(reason) do
    %__MODULE__{property_name: property_name, reason: reason}
  end
end

defmodule MQTT.ErrorContext.MalformedPacket do
  defstruct [:reason]

  def new(reason) when is_nil(reason) or is_binary(reason) do
    %__MODULE__{reason: reason}
  end
end
