defmodule MQTT.Packet.Publish do
  alias MQTT.PacketEncoder

  @control_packet_type 3

  defstruct [:flags, :packet_identifier, :properties, :payload, :topic_name]

  def encode!(%__MODULE__{} = packet) do
    flags = __MODULE__.Flags.encode!(packet.flags)

    topic_name = PacketEncoder.encode_utf8_string(packet.topic_name)
    properties = PacketEncoder.encode_properties(packet.properties)

    variable_header =
      if packet.flags.qos > 0 do
        packet_identifier = PacketEncoder.encode_two_byte_integer(packet.packet_identifier)

        topic_name <> packet_identifier <> properties
      else
        topic_name <> properties
      end

    payload = __MODULE__.Payload.encode!(packet.payload)

    remaining_length = byte_size(variable_header) + byte_size(payload)

    fixed_header =
      <<@control_packet_type::4, flags::bitstring>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header <> payload
  end
end

defmodule MQTT.Packet.Publish.Flags do
  defstruct dup?: false,
            qos: 0,
            retain?: false

  def encode!(%__MODULE__{} = flags) do
    dup_flag = if flags.dup?, do: 1, else: 0
    retain_flag = if flags.retain?, do: 1, else: 0

    <<dup_flag::1, flags.qos::2, retain_flag::1>>
  end
end

defmodule MQTT.Packet.Publish.Payload do
  defstruct [:data]

  def encode!(%__MODULE__{data: data}), do: data
end
