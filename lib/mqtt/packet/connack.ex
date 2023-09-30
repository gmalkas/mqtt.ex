defmodule MQTT.Packet.Connack do
  import MQTT.PacketDecoder, only: [decode_properties: 1, decode_reason_code: 2]

  defstruct [:connect_acknowledge_flags, :connect_reason_code, :properties]

  def decode(data) do
    with {:ok, connect_acknowledge_flags, rest} <- decode_connect_acknowledge_flags(data),
         {:ok, connect_reason_code, rest} <- decode_reason_code(:connack, rest),
         {:ok, properties, _, rest} <- decode_properties(rest),
         {:ok, properties} <- validate_properties(properties) do
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

  defp validate_properties(properties) do
    __MODULE__.Properties.from_decoder(properties)
  end
end

defmodule MQTT.Packet.Connack.Properties do
  alias MQTT.Error

  @properties ~w(
    session_expiry_interval receive_maximum maximum_qos
    retain_available maximum_packet_size assigned_client_identifier
    topic_alias_maximum reason_string user_properties
    wildcard_subscription_available subscription_identifiers_available
    shared_subscription_available server_keep_alive response_information
    server_reference authentication_method authentication_data
  )a

  defstruct @properties

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
        {:ok, nil}

      [value] ->
        validate_property_value(property_name, value)

      _values ->
        {:error, Error.duplicated_property(property_name, Enum.count(values))}
    end
  end

  defp validate_property_value(_, value), do: {:ok, value}
end
