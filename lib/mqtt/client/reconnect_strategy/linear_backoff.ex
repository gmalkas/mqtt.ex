defmodule MQTT.Client.ReconnectStrategy.LinearBackoff do
  defstruct initial_delay: 0, step_delay: 1, max_delay: 30

  def new(args \\ []) when is_list(args) do
    struct!(__MODULE__, args)
  end

  def delay(%__MODULE__{} = config, retry_count) when is_integer(retry_count) do
    delay = config.initial_delay + retry_count * config.step_delay

    min(delay, config.max_delay)
  end
end
