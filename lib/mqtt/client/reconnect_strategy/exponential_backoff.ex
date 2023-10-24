defmodule MQTT.Client.ReconnectStrategy.ExponentialBackoff do
  defstruct initial_delay: 1, base: 2, max_delay: 30

  def new(args \\ []) when is_list(args) do
    struct!(__MODULE__, args)
  end

  def delay(%__MODULE__{} = config, retry_count) when is_integer(retry_count) do
    delay = config.initial_delay + Integer.pow(config.base, retry_count)

    min(delay, config.max_delay)
  end
end
