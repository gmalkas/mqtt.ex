defmodule MQTT.Packet.Pubrel do
  alias MQTT.{PacketEncoder, PacketDecoder}

  @control_packet_type 6
  @control_packet_flags 2

  defstruct [:packet_identifier, :reason_code, :properties]

  def decode(data, remaining_length) do
    with {:ok, packet_identifier, rest} <- PacketDecoder.decode_packet_identifier(data),
         {:ok, reason_code, rest} <- decode_reason_code(rest, remaining_length),
         {:ok, properties, _, rest} <- decode_properties(rest, remaining_length),
         {:ok, properties} <- __MODULE__.Properties.from_decoder(properties) do
      {:ok,
       %__MODULE__{
         packet_identifier: packet_identifier,
         reason_code: reason_code,
         properties: properties
       }, rest}
    end
  end

  def encode!(%__MODULE__{} = packet) do
    packet_identifier = PacketEncoder.encode_two_byte_integer(packet.packet_identifier)

    variable_header =
      if skip_reason_code_and_properties?(packet) do
        packet_identifier
      else
        reason_code = PacketEncoder.encode_reason_code(packet.reason_code)
        properties = __MODULE__.Properties.encode!(packet.properties)

        packet_identifier <> reason_code <> properties
      end

    remaining_length = byte_size(variable_header)

    fixed_header =
      <<@control_packet_type::4, @control_packet_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header
  end

  defp decode_reason_code(data, 2), do: {:ok, :success, data}
  defp decode_reason_code(data, _), do: PacketDecoder.decode_reason_code(:pubrel, data)

  defp decode_properties(data, 2), do: {:ok, [], 0, data}
  defp decode_properties(data, _), do: PacketDecoder.decode_properties(data)

  defp skip_reason_code_and_properties?(packet) do
    packet.reason_code == :success && __MODULE__.Properties.empty?(packet.properties)
  end
end

defmodule MQTT.Packet.Pubrel.Properties do
  use MQTT.PacketProperties, properties: ~w(reason_string user_property)a
end
