defmodule MQTT.Packet.Suback do
  import MQTT.PacketDecoder, only: [decode_properties: 1, decode_packet_identifier: 1]

  alias MQTT.{Packet, PacketEncoder}

  @control_packet_type 9
  @control_packet_flags 0

  defstruct [:packet_identifier, :properties, :payload]

  def decode(data, remaining_length) do
    with {:ok, packet_identifier, rest} <- decode_packet_identifier(data),
         {:ok, properties, properties_length, rest} <- decode_properties(rest),
         {:ok, properties} <- __MODULE__.Properties.from_decoder(properties),
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

  def encode!(%__MODULE__{} = packet) do
    packet_identifier = PacketEncoder.encode_two_byte_integer(packet.packet_identifier)
    properties = __MODULE__.Properties.encode!(packet.properties)

    variable_header = packet_identifier <> properties
    payload = __MODULE__.Payload.encode!(packet.payload)

    remaining_length = byte_size(variable_header) + byte_size(payload)

    fixed_header =
      <<@control_packet_type::4, @control_packet_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header <> payload
  end

  defp payload_length(remaining_length, properties_length) do
    remaining_length - properties_length - Packet.wire_byte_size(:packet_identifier)
  end

  defp decode_payload(data, payload_length), do: __MODULE__.Payload.decode(data, payload_length)
end

defmodule MQTT.Packet.Suback.Properties do
  use MQTT.PacketProperties, properties: ~w(reason_string user_property)a
end

defmodule MQTT.Packet.Suback.Payload do
  import MQTT.PacketDecoder, only: [decode_reason_code: 2]

  alias MQTT.{Packet, PacketEncoder}

  defstruct [:reason_codes]

  def decode(data, payload_length) do
    with {:ok, reason_codes, rest} <- do_decode_payload(data, payload_length) do
      {:ok, %__MODULE__{reason_codes: reason_codes}, rest}
    end
  end

  def encode!(%__MODULE__{reason_codes: reason_codes}) do
    reason_codes
    |> Enum.map(&PacketEncoder.encode_byte(Packet.reason_code_by_name!(&1)))
    |> Enum.join(<<>>)
  end

  defp do_decode_payload(data, length, reason_codes \\ [])

  defp do_decode_payload(data, 0, reason_codes), do: {:ok, Enum.reverse(reason_codes), data}

  defp do_decode_payload(data, length, reason_codes) do
    with {:ok, reason_code, rest} <- decode_reason_code(:suback, data) do
      do_decode_payload(rest, length - 1, [reason_code | reason_codes])
    end
  end
end
