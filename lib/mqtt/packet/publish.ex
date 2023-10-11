defmodule MQTT.Packet.Publish do
  import MQTT.PacketDecoder,
    only: [decode_properties: 1, decode_packet_identifier: 1, decode_utf8_string: 1]

  alias MQTT.{Packet, PacketEncoder}

  @control_packet_type 3

  defstruct [:flags, :packet_identifier, :properties, :payload, :topic_name]

  def decode(data, flags, remaining_length) do
    with {:ok, flags} <- __MODULE__.Flags.from_wire(flags),
         {:ok, topic_name, rest} <- decode_utf8_string(data),
         {:ok, packet_identifier, rest} <- decode_packet_identifier(rest, flags),
         {:ok, properties, properties_length, rest} <- decode_properties(rest),
         {:ok, payload, rest} <-
           decode_payload(
             rest,
             payload_length(flags, remaining_length, topic_name, properties_length)
           ) do
      {:ok,
       %__MODULE__{
         topic_name: topic_name,
         packet_identifier: packet_identifier,
         flags: flags,
         payload: payload,
         properties: properties
       }, rest}
    end
  end

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

  defp decode_packet_identifier(data, flags) do
    if flags.qos > 0 do
      decode_packet_identifier(data)
    else
      {:ok, nil, data}
    end
  end

  defp payload_length(flags, remaining_length, topic_name, properties_length) do
    packet_identifier_length =
      if flags.qos > 0 do
        Packet.wire_byte_size(:packet_identifier)
      else
        0
      end

    topic_name_length = Packet.wire_byte_size({:utf8_string, topic_name})

    remaining_length - properties_length - topic_name_length - packet_identifier_length
  end

  defp decode_payload(data, payload_length), do: __MODULE__.Payload.decode(data, payload_length)
end

defmodule MQTT.Packet.Publish.Flags do
  alias MQTT.Error

  defstruct dup?: false,
            qos: 0,
            retain?: false

  def encode!(%__MODULE__{} = flags) do
    dup_flag = if flags.dup?, do: 1, else: 0
    retain_flag = if flags.retain?, do: 1, else: 0

    <<dup_flag::1, flags.qos::2, retain_flag::1>>
  end

  def from_wire(%{dup: dup, qos: qos, retain: retain}) do
    dup? = dup == 1
    retain? = retain == 1

    if 0 <= qos && qos <= 2 do
      {:ok,
       %__MODULE__{
         dup?: dup?,
         qos: qos,
         retain?: retain?
       }}
    else
      {:error, Error.malformed_packet()}
    end
  end
end

defmodule MQTT.Packet.Publish.Payload do
  defstruct [:data]

  def decode(data, payload_length) do
    if byte_size(data) >= payload_length do
      <<payload::binary-size(payload_length)>> <> rest = data

      {:ok, %__MODULE__{data: payload}, rest}
    else
      {:error, :incomplete_packet, data}
    end
  end

  def encode!(%__MODULE__{data: data}), do: data
end
