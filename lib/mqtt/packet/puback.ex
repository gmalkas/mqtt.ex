defmodule MQTT.Packet.Puback do
  alias MQTT.PacketDecoder

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

  defp decode_reason_code(data, 2), do: {:ok, :success, data}
  defp decode_reason_code(data, _), do: PacketDecoder.decode_reason_code(:puback, data)

  defp decode_properties(data, 2), do: {:ok, [], 0, data}
  defp decode_properties(data, _), do: PacketDecoder.decode_properties(data)
end

defmodule MQTT.Packet.Puback.Properties do
  use MQTT.PacketProperties, properties: ~w(reason_string user_property)a
end
