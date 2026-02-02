defmodule MQTT.Packet.Disconnect do
  alias MQTT.{PacketDecoder, PacketEncoder}

  @control_packet_type 14
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
    reason_code = PacketEncoder.encode_reason_code(packet.reason_code)
    properties = __MODULE__.Properties.encode!(packet.properties)

    variable_header =
      reason_code <> properties

    remaining_length = byte_size(variable_header)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header
  end

  defp decode_reason_code(data, 0), do: {:ok, :success, data}
  defp decode_reason_code(data, _), do: PacketDecoder.decode_reason_code(:disconnect, data)

  defp decode_properties(data, remaining_length) when remaining_length < 2, do: {:ok, [], 0, data}
  defp decode_properties(data, _), do: PacketDecoder.decode_properties(data)
end

defmodule MQTT.Packet.Disconnect.Properties do
  use MQTT.PacketProperties,
    properties: ~w(session_expiry_interval reason_string user_property server_reference)a
end
