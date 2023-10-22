defmodule MQTT.Packet.Connack do
  import MQTT.PacketDecoder, only: [decode_properties: 1, decode_reason_code: 2]
  alias MQTT.PacketEncoder

  @control_packet_type 2
  @fixed_header_flags 0

  defstruct [:flags, :reason_code, :properties]

  def decode(data) do
    with {:ok, flags, rest} <- __MODULE__.Flags.decode(data),
         {:ok, reason_code, rest} <- decode_reason_code(:connack, rest),
         {:ok, properties, _, rest} <- decode_properties(rest),
         {:ok, properties} <- validate_properties(properties) do
      {:ok,
       %__MODULE__{
         flags: flags,
         reason_code: reason_code,
         properties: properties
       }, rest}
    end
  end

  def encode!(%__MODULE__{} = packet) do
    connect_acknowledge_flags = __MODULE__.Flags.encode!(packet.flags)
    reason_code = PacketEncoder.encode_reason_code(packet.reason_code)
    properties = __MODULE__.Properties.encode!(packet.properties)

    variable_header =
      connect_acknowledge_flags <> reason_code <> properties

    remaining_length = byte_size(variable_header)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header
  end

  defp validate_properties(properties) do
    __MODULE__.Properties.from_decoder(properties)
  end
end

defmodule MQTT.Packet.Connack.Flags do
  defstruct session_present?: false

  def decode(<<0::7, session_present_flag::1>> <> rest) do
    {:ok, %__MODULE__{session_present?: session_present_flag == 1}, rest}
  end

  def decode(data) when bit_size(data) < 8 do
    {:error, :incomplete_packet, data}
  end

  def encode!(%__MODULE__{} = flags) do
    session_present_flag =
      if flags.session_present? do
        1
      else
        0
      end

    <<0::7, session_present_flag::1>>
  end
end

defmodule MQTT.Packet.Connack.Properties do
  alias MQTT.{Error, PacketEncoder}

  @properties ~w(
    session_expiry_interval receive_maximum maximum_qos
    retain_available maximum_packet_size assigned_client_identifier
    topic_alias_maximum reason_string user_properties
    wildcard_subscription_available subscription_identifiers_available
    shared_subscription_available server_keep_alive response_information
    server_reference authentication_method authentication_data
  )a

  defstruct @properties

  def encode!(%__MODULE__{} = properties) do
    properties
    |> Map.from_struct()
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
    |> PacketEncoder.encode_properties()
  end

  def from_decoder(properties) when is_list(properties) do
    {properties, errors} =
      Enum.reduce(@properties, {[], []}, fn property, {acc, errors} ->
        case validate_property(property, Keyword.get_values(properties, property)) do
          {:ok, value} -> {[{property, value} | acc], errors}
          {:error, error} -> {acc, [error | errors]}
        end
      end)

    if length(errors) == 0 do
      {:ok, struct!(__MODULE__, properties)}
    else
      {:error, errors}
    end
  end

  defp validate_property(:user_property, values) do
    {:ok, values}
  end

  defp validate_property(property_name, values) do
    case values do
      [] ->
        {:ok, default_property_value(property_name)}

      [value] ->
        validate_property_value(property_name, value)

      _values ->
        {:error, Error.duplicated_property(property_name, Enum.count(values))}
    end
  end

  defp validate_property_value(_, value), do: {:ok, value}

  defp default_property_value(:retain_available), do: true
  defp default_property_value(:topic_alias_maximum), do: 0
  defp default_property_value(_), do: nil
end
