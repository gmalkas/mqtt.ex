defmodule MQTT.Packet.Auth.Properties do
  use MQTT.PacketProperties, properties: ~w(
    authentication_method authentication_data reason_string user_property
  )a
end

defmodule MQTT.Packet.Auth do
  alias MQTT.{PacketDecoder, PacketEncoder}

  @control_packet_type 15
  @fixed_header_flags 0

  defstruct [:reason_code, :properties]

  def decode(data, remaining_length) do
    with {:ok, reason_code, rest} <- decode_reason_code(data, remaining_length),
         {:ok, properties, _, rest} <- decode_properties(rest, remaining_length),
         {:ok, properties} <- __MODULE__.Properties.from_decoder(properties) do
      {:ok,
       %__MODULE__{
         reason_code: reason_code,
         properties: properties
       }, rest}
    end
  end

  def encode!(%__MODULE__{} = packet) do
    variable_header =
      if skip_reason_code_and_properties?(packet) do
        <<>>
      else
        reason_code = PacketEncoder.encode_reason_code(packet.reason_code)
        properties = __MODULE__.Properties.encode!(packet.properties)

        reason_code <> properties
      end

    remaining_length = byte_size(variable_header)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header
  end

  defp decode_reason_code(data, 0), do: {:ok, :success, data}
  defp decode_reason_code(data, _), do: PacketDecoder.decode_reason_code(:auth, data)

  defp decode_properties(data, 0), do: {:ok, [], 0, data}
  defp decode_properties(data, _), do: PacketDecoder.decode_properties(data)

  defp skip_reason_code_and_properties?(packet) do
    packet.reason_code == :success && __MODULE__.Properties.empty?(packet.properties)
  end
end
