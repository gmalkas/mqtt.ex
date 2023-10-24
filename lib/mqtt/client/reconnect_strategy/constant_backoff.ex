defmodule MQTT.Client.ReconnectStrategy.ConstantBackoff do
  defstruct [:delay_s]

  def new(delay_s) when is_integer(delay_s) do
    %__MODULE__{delay_s: delay_s}
  end

  def delay(%__MODULE__{} = config, retry_count) when is_integer(retry_count) do
    config.delay_s
  end
end
