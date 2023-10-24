defmodule MQTT.Client.ReconnectStrategy.LinearBackoffTest do
  use ExUnit.Case, async: true

  alias MQTT.Client.ReconnectStrategy

  test "starts at an initial value and linearly increases until a max is reached" do
    strategy = ReconnectStrategy.LinearBackoff.new(initial_delay: 5, step_delay: 1, max_delay: 10)

    assert 5 = ReconnectStrategy.LinearBackoff.delay(strategy, 0)
    assert 6 = ReconnectStrategy.LinearBackoff.delay(strategy, 1)
    assert 7 = ReconnectStrategy.LinearBackoff.delay(strategy, 2)
    assert 10 = ReconnectStrategy.LinearBackoff.delay(strategy, 5)
    assert 10 = ReconnectStrategy.LinearBackoff.delay(strategy, 15)
  end
end
