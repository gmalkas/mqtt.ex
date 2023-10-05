defmodule MQTT.TransportError do
  defexception [:reason]

  def message(%__MODULE__{reason: reason}) do
    inspect(reason)
  end
end
