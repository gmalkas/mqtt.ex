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

      decode_packet(packet_type, flags, rest)
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
    {:error, :incomplete}
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

  defp decode_header_flags(:publish, <<dup, qos::2, retain>>),
    do: {:ok, %{dup: dup, qos: qos, retain: retain}}

  defp decode_header_flags(:puback, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pubrel, <<0::1, 0::1, 1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pubcomp, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:subscribe, <<0::1, 0::1, 1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:suback, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:unsubscribe, <<0::1, 0::1, 1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:unsuback, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pingreq, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:pingresp, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:disconnect, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}
  defp decode_header_flags(:auth, <<0::1, 0::1, 0::1, 0::1>>), do: {:ok, %{}}

  defp decode_header_flags(_type, _flags),
    do: {:error, Error.malformed_packet("unexpected flags")}

  defp decode_remaining_length(data) do
    decode_variable_byte_integer(data)
  end

  defp decode_packet(:connack, _flags, data) do
    Packet.Connack.decode(data)
  end

  def decode_properties(data) do
    with {:ok, length, rest} <- decode_variable_byte_integer(data) do
      decode_properties(rest, length)
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
         {:ok, value, rest} <- decode_property(type, rest) do
      {:ok, name, value, rest}
    end
  end

  defp property_name_and_type(identifier, data) do
    case Packet.property_by_identifier(identifier) do
      {:ok, {name, type}} -> {:ok, name, type, data}
      :error -> {:error, :unknown_property, data}
    end
  end

  defp decode_property(:session_expiry_interval, data) do
    decode_four_byte_integer(data)
  end

  defp decode_property(:authentication_method, data) do
    decode_four_byte_integer(data)
  end

  defp decode_property(:authentication_data, data) do
    decode_binary_data(data)
  end

  defp decode_property(:request_problem_information, data) do
    decode_byte(data)
  end

  defp decode_property(:request_response_information, data) do
    decode_byte(data)
  end

  defp decode_property(:receive_maximum, data) do
    decode_two_byte_integer(data)
  end

  defp decode_property(:topic_alias_maximum, data) do
    decode_two_byte_integer(data)
  end

  defp decode_property(:user_property, data) do
    decode_utf8_string_pair(data)
  end

  defp decode_property(:maximum_packet_size, data) do
    decode_four_byte_integer(data)
  end

  def decode_byte(<<value::8>> <> rest) do
    {:ok, value, rest}
  end

  def decode_byte(data) when bit_size(data) < 8 do
    {:error, :incomplete}
  end

  def decode_two_byte_integer(<<value::16-big>> <> rest) do
    {:ok, value, rest}
  end

  def decode_two_byte_integer(data) when bit_size(data) < 16 do
    {:error, :incomplete}
  end

  def decode_four_byte_integer(<<value::32-big>> <> rest) do
    {:ok, value, rest}
  end

  def decode_four_byte_integer(data) when bit_size(data) < 32 do
    {:error, :incomplete}
  end

  def decode_binary_data(data) do
    with {:ok, binary_data_length, rest} <- decode_two_byte_integer(data) do
      decode_binary_data(rest, binary_data_length)
    end
  end

  def decode_binary_data(data, 0), do: {:ok, "", data}

  def decode_binary_data(data, length) when byte_size(data) < length do
    {:error, :incomplete}
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
    {:error, :incomplete}
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
    {:error, :incomplete}
  end
end
