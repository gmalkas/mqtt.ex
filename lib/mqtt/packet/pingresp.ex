defmodule MQTT.Packet.Pingresp do
  defstruct []

  def decode(data, 0) do
    {:ok, %__MODULE__{}, data}
  end
end
