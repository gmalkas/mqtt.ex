defmodule MQTT.Client.ReconnectStrategy.ExponentialBackoffTest do
  use ExUnit.Case, async: true

  alias MQTT.Client.ReconnectStrategy

  test "starts at an initial value and linearly increases until a max is reached" do
    strategy = ReconnectStrategy.ExponentialBackoff.new(initial_delay: 5, base: 2, max_delay: 10)

    assert 6 = ReconnectStrategy.ExponentialBackoff.delay(strategy, 0)
    assert 7 = ReconnectStrategy.ExponentialBackoff.delay(strategy, 1)
    assert 9 = ReconnectStrategy.ExponentialBackoff.delay(strategy, 2)
    assert 10 = ReconnectStrategy.ExponentialBackoff.delay(strategy, 5)
    assert 10 = ReconnectStrategy.ExponentialBackoff.delay(strategy, 15)
  end
end
