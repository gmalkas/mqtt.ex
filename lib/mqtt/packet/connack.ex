defmodule MQTT.Packet.Connack do
  import MQTT.PacketDecoder, only: [decode_properties: 1, decode_reason_code: 2]

  defstruct [:connect_acknowledge_flags, :connect_reason_code, :properties]

  def decode(data) do
    with {:ok, connect_acknowledge_flags, rest} <- decode_connect_acknowledge_flags(data),
         {:ok, connect_reason_code, rest} <- decode_reason_code(:connack, rest),
         {:ok, properties, _, rest} <- decode_properties(rest) do
      {:ok,
       %__MODULE__{
         connect_acknowledge_flags: connect_acknowledge_flags,
         connect_reason_code: connect_reason_code,
         properties: properties
       }, rest}
    end
  end

  defp decode_connect_acknowledge_flags(<<0::7, session_present_flag::1>> <> rest) do
    {:ok, %{session_present?: session_present_flag == 1}, rest}
  end

  defp decode_connect_acknowledge_flags(data) when bit_size(data) < 8 do
    {:error, :incomplete, data}
  end
end
