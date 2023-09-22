defmodule MQTT.Packet.Subscribe do
  alias MQTT.PacketEncoder

  @control_packet_type 8
  @fixed_header_flags 2

  defstruct [:packet_identifier, :properties, :payload]

  def encode!(%__MODULE__{} = packet) do
    packet_identifier = PacketEncoder.encode_two_byte_integer(packet.packet_identifier)
    properties = PacketEncoder.encode_properties(packet.properties)

    variable_header = packet_identifier <> properties

    payload = __MODULE__.Payload.encode!(packet.payload)

    remaining_length = byte_size(variable_header) + byte_size(payload)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header <> payload
  end
end

defmodule MQTT.Packet.Subscribe.Payload do
  alias MQTT.{PacketEncoder, Packet.Subscribe}

  defstruct [:topic_filters]

  def encode!(%__MODULE__{} = payload) do
    payload.topic_filters
    |> Enum.map(fn {topic_filter, options} ->
      PacketEncoder.encode_utf8_string(topic_filter) <>
        Subscribe.SubscriptionOptions.encode!(options)
    end)
    |> Enum.join(<<>>)
  end
end

defmodule MQTT.Packet.Subscribe.SubscriptionOptions do
  defstruct max_qos: 0, no_local?: false, retain_as_published?: false, retain_handling: 0

  def encode!(%__MODULE__{} = options) do
    rap = if options.retain_as_published?, do: 1, else: 0
    nl = if options.no_local?, do: 1, else: 0

    <<0::2, options.retain_handling::2, rap::1, nl::1, options.max_qos::2>>
  end

  def from_params(params) when is_list(params) do
    struct!(__MODULE__, params)
  end
end
