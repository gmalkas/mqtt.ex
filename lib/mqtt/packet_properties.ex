defmodule MQTT.PacketProperties do
  @doc false
  defmacro __using__(opts) do
    quote do
      alias MQTT.{Error, PacketEncoder}

      @properties unquote(opts[:properties])
      defstruct @properties

      def empty?(%__MODULE__{} = properties) do
        properties
        |> to_list()
        |> Enum.all?(fn {_, value} -> is_nil(value) end)
      end

      def encode!(%__MODULE__{} = properties) do
        properties
        |> to_list()
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

      defp to_list(%__MODULE__{} = properties) do
        properties
        |> Map.from_struct()
        |> Enum.flat_map(fn
          {key, values} when is_list(values) -> Enum.map(values, &{key, &1})
          {key, value} -> [{key, value}]
        end)
        |> Enum.reject(fn {_, value} -> is_nil(value) end)
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
  end
end
