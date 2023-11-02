defmodule MQTT.PacketDecoder do
  require Logger

  alias MQTT.{Error, Packet}

  @max_variable_byte_integer_byte_count 4

  def decode(data) when is_binary(data) do
    decode_header(data)
  end

  defp decode_header(data) when is_binary(data) do
    with {:ok, packet_type, flags, remaining_length, rest} <- decode_fixed_header(data) do
      Logger.debug(
        "event=decoded_fixed_header, packet_type=#{packet_type}, flags=#{inspect(flags)}, remaining_length=#{remaining_length}"
      )

      decode_packet(packet_type, flags, remaining_length, rest)
    end
  end

  defp decode_fixed_header(<<packet_type_value::4, flags::4-bitstring>> <> rest) do
    with {:ok, packet_type} <- packet_type(packet_type_value),
         {:ok, flags} <- decode_header_flags(packet_type, flags),
         {:ok, remaining_length, rest} <- decode_remaining_length(rest) do
      {:ok, packet_type, flags, remaining_length, rest}
    end
  end

  defp decode_fixed_header(rest) when bit_size(rest) < 8 do
    {:error, :incomplete_packet}
  end

  defp decode_fixed_header(_rest), do: {:error, Error.malformed_packet("unexpected fixed header")}

  defp packet_type(packet_type_value) do
    case Packet.packet_type_from_value(packet_type_value) do
      {:ok, packet_type} -> {:ok, packet_type}
      :error -> {:error, :unknown_packet_type, packet_type_value}
    end
  end

  defp decode_header_flags(:connect, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:connack, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}

  defp decode_header_flags(:publish, <<dup::1, qos::2, retain::1>>),
    do: {:ok, %{dup: dup, qos: qos, retain: retain}}

  defp decode_header_flags(:auth, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:puback, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pubrec, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pubrel, <<0::1, 0::1, 1::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pubcomp, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:subscribe, <<0::1, 0::1, 1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:suback, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:unsubscribe, <<0::1, 0::1, 1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:unsuback, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pingreq, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pingresp, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:disconnect, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}

  defp decode_header_flags(_type, _flags),
    do: {:error, Error.malformed_packet("unexpected flags")}

  defp decode_remaining_length(data) do
    decode_variable_byte_integer(data)
  end

  defp decode_packet(:auth, _flags, remaining_length, data) do
    Packet.Auth.decode(data, remaining_length)
  end

  defp decode_packet(:connack, _flags, _, data) do
    Packet.Connack.decode(data)
  end

  defp decode_packet(:pingresp, _flags, remaining_length, data) do
    Packet.Pingresp.decode(data, remaining_length)
  end

  defp decode_packet(:suback, _flags, remaining_length, data) do
    Packet.Suback.decode(data, remaining_length)
  end

  defp decode_packet(:unsuback, _flags, remaining_length, data) do
    Packet.Unsuback.decode(data, remaining_length)
  end

  defp decode_packet(:publish, flags, remaining_length, data) do
    Packet.Publish.decode(data, flags, remaining_length)
  end

  defp decode_packet(:puback, _flags, remaining_length, data) do
    Packet.Puback.decode(data, remaining_length)
  end

  defp decode_packet(:pubrec, _flags, remaining_length, data) do
    Packet.Pubrec.decode(data, remaining_length)
  end

  defp decode_packet(:pubrel, _flags, remaining_length, data) do
    Packet.Pubrel.decode(data, remaining_length)
  end

  defp decode_packet(:pubcomp, _flags, remaining_length, data) do
    Packet.Pubcomp.decode(data, remaining_length)
  end

  def decode_properties(data) do
    with {:ok, length, rest} <- decode_variable_byte_integer(data),
         {:ok, properties, rest} <- decode_properties(rest, length) do
      {:ok, properties, length + Packet.wire_byte_size({:variable_byte_integer, length}), rest}
    end
  end

  def decode_properties(data, length, properties \\ [])

  def decode_properties(data, 0, properties), do: {:ok, properties, data}

  def decode_properties(data, properties_length, properties) do
    with {:ok, identifier, value, rest} <- decode_property(data) do
      property_length = byte_size(data) - byte_size(rest)

      decode_properties(rest, properties_length - property_length, [
        {identifier, value} | properties
      ])
    end
  end

  defp decode_property(data) do
    with {:ok, identifier, rest} <- decode_variable_byte_integer(data),
         {:ok, name, type, rest} <- property_name_and_type(identifier, rest),
         {:ok, value, rest} <- decode_property_value(type, rest) do
      {:ok, name, value, rest}
    end
  end

  defp property_name_and_type(identifier, data) do
    case Packet.property_by_identifier(identifier) do
      {:ok, {name, type}} -> {:ok, name, type, data}
      :error -> {:error, :unknown_property, data}
    end
  end

  defp decode_property_value(:binary, data), do: decode_binary_data(data)
  defp decode_property_value(:utf8_string, data), do: decode_utf8_string(data)

  def decode_byte(<<value::8>> <> rest) do
    {:ok, value, rest}
  end

  def decode_byte(data) when bit_size(data) < 8 do
    {:error, :incomplete_packet}
  end

  def decode_two_byte_integer(<<value::16-big>> <> rest) do
    {:ok, value, rest}
  end

  def decode_two_byte_integer(data) when bit_size(data) < 16 do
    {:error, :incomplete_packet}
  end

  def decode_four_byte_integer(<<value::32-big>> <> rest) do
    {:ok, value, rest}
  end

  def decode_four_byte_integer(data) when bit_size(data) < 32 do
    {:error, :incomplete_packet}
  end

  def decode_binary_data(data) do
    with {:ok, binary_data_length, rest} <- decode_two_byte_integer(data) do
      decode_binary_data(rest, binary_data_length)
    end
  end

  def decode_binary_data(data, 0), do: {:ok, "", data}

  def decode_binary_data(data, length) when byte_size(data) < length do
    {:error, :incomplete_packet}
  end

  def decode_binary_data(data, length) do
    <<binary_data::binary-size(length)>> <> rest = data

    {:ok, binary_data, rest}
  end

  def decode_utf8_string(data) do
    with {:ok, string_length, rest} <- decode_two_byte_integer(data) do
      decode_utf8_string(rest, string_length)
    end
  end

  def decode_utf8_string(data, 0), do: {:ok, "", data}

  def decode_utf8_string(data, string_length) when byte_size(data) < string_length do
    {:error, :incomplete_packet}
  end

  def decode_utf8_string(data, string_length) do
    <<string_data::binary-size(string_length)>> <> rest = data

    # TODO: Check string does not contain disallowed UTF-8 codepoints
    if String.valid?(string_data) do
      {:ok, string_data, rest}
    else
      {:error, Error.malformed_packet("invalid UTF-8 string")}
    end
  end

  def decode_utf8_string_pair(data) do
    with {:ok, first_string, rest} <- decode_utf8_string(data),
         {:ok, second_string, rest} <- decode_utf8_string(rest) do
      {:ok, {first_string, second_string}, rest}
    end
  end

  def decode_variable_byte_integer(data, values \\ [])

  def decode_variable_byte_integer(<<continuation::1, value::7>> <> rest, values) do
    values = [value | values]
    byte_count = length(values)
    continue? = continuation == 1

    cond do
      continue? && byte_count < @max_variable_byte_integer_byte_count ->
        decode_variable_byte_integer(rest, values)

      continue? ->
        {:error, Error.malformed_packet("variable byte integer cannot have more than four bytes")}

      true ->
        value =
          values
          |> Enum.reverse()
          |> Enum.with_index()
          |> Enum.map(fn {value, i} -> value * Integer.pow(128, i) end)
          |> Enum.sum()

        {:ok, value, rest}
    end
  end

  def decode_variable_byte_integer(rest, _values) when bit_size(rest) < 8 do
    {:error, :incomplete_packet}
  end

  def decode_packet_identifier(data), do: decode_two_byte_integer(data)

  def decode_reason_code(packet_type, <<reason_code::8>> <> rest) do
    case Packet.reason_code_name_by_packet_type_and_value(packet_type, reason_code) do
      {:ok, name} -> {:ok, name, rest}
      :error -> {:error, :unknown_reason_code, rest}
    end
  end

  def decode_reason_code(_, data) when byte_size(data) < 1 do
    {:error, :incomplete_packet, data}
  end
end
