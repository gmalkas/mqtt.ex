defmodule MQTT.Packet.Unsuback do
  import MQTT.PacketDecoder, only: [decode_properties: 1, decode_packet_identifier: 1]

  alias MQTT.Packet

  defstruct [:packet_identifier, :properties, :payload]

  def decode(data, remaining_length) do
    with {:ok, packet_identifier, rest} <- decode_packet_identifier(data),
         {:ok, properties, properties_length, rest} <- decode_properties(rest),
         {:ok, payload, rest} <-
           decode_payload(rest, payload_length(remaining_length, properties_length)) do
      {:ok,
       %__MODULE__{
         packet_identifier: packet_identifier,
         payload: payload,
         properties: properties
       }, rest}
    end
  end

  defp payload_length(remaining_length, properties_length) do
    remaining_length - properties_length - Packet.wire_byte_size(:packet_identifier)
  end

  defp decode_payload(data, payload_length), do: __MODULE__.Payload.decode(data, payload_length)
end

defmodule MQTT.Packet.Unsuback.Payload do
  import MQTT.PacketDecoder, only: [decode_reason_code: 2]

  defstruct [:reason_codes]

  def decode(data, payload_length) do
    with {:ok, reason_codes, rest} <- do_decode_payload(data, payload_length) do
      {:ok, %__MODULE__{reason_codes: reason_codes}, rest}
    end
  end

  def do_decode_payload(data, length, reason_codes \\ [])

  def do_decode_payload(data, 0, reason_codes), do: {:ok, Enum.reverse(reason_codes), data}

  def do_decode_payload(data, length, reason_codes) do
    with {:ok, reason_code, rest} <- decode_reason_code(:unsuback, data) do
      do_decode_payload(rest, length - 1, [reason_code | reason_codes])
    end
  end
end
