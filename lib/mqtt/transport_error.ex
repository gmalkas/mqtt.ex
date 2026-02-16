defmodule MQTT.TransportError do
  @type t :: %__MODULE__{reason: term()}

  defexception [:reason]

  def message(%__MODULE__{reason: reason}) do
    inspect(reason)
  end
end
