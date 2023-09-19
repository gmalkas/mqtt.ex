defmodule MQTT.PacketEncoder do
  import Bitwise

  alias MQTT.Packet

  @max_two_byte_integer_value 0xFFFF
  @max_four_byte_integer_value 0xFFFF_FFFF
  @max_variable_byte_integer_value 268_435_455

  def encode(:byte, value), do: encode_byte(value)
  def encode(:two_byte_integer, value), do: encode_two_byte_integer(value)
  def encode(:four_byte_integer, value), do: encode_four_byte_integer(value)
  def encode(:utf8_string, value), do: encode_utf8_string(value)

  def encode(:utf8_string_pair, {value_1, value_2}),
    do: encode_utf8_string(value_1) <> encode_utf8_string(value_2)

  def encode_byte(value) when is_integer(value), do: <<value>>
  def encode_byte(value) when is_binary(value), do: value

  def encode_two_byte_integer(value)
      when is_integer(value) and value >= 0 and value <= @max_two_byte_integer_value do
    <<value::16-big>>
  end

  def encode_four_byte_integer(value)
      when is_integer(value) and value >= 0 and value <= @max_four_byte_integer_value do
    <<value::32-big>>
  end

  def encode_variable_byte_integer(0), do: <<0::8>>

  def encode_variable_byte_integer(value) when value < @max_variable_byte_integer_value do
    do_encode_variable_byte_integer(value)
  end

  def encode_binary_data(value) when is_binary(value) do
    encode_two_byte_integer(byte_size(value)) <> value
  end

  def encode_utf8_string(value) when is_binary(value) do
    # TODO: Enforce valid UTF-8 string
    encode_two_byte_integer(byte_size(value)) <> value
  end

  def encode_properties(properties) do
    encoded_properties =
      properties
      |> Enum.map(&encode_property/1)
      |> Enum.join(<<>>)

    property_length = encode_variable_byte_integer(byte_size(encoded_properties))

    property_length <> encoded_properties
  end

  defp encode_property({name, value}) do
    {property_identifier, property_type} = Packet.property_by_name!(name)

    encode_variable_byte_integer(property_identifier) <> encode(property_type, value)
  end

  defp do_encode_variable_byte_integer(0), do: <<>>

  defp do_encode_variable_byte_integer(value) when value < @max_variable_byte_integer_value do
    encoded_byte = rem(value, 128)
    x = div(value, 128)

    encoded_byte =
      if x > 0 do
        encoded_byte ||| 128
      else
        encoded_byte
      end

    <<encoded_byte::8>> <> do_encode_variable_byte_integer(x)
  end
end
