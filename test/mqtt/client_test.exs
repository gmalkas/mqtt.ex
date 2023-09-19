defmodule MQTT.ClientTest do
  use ExUnit.Case, async: false

  @client_id_byte_size 12
  @ip_address "127.0.0.1"

  test "connects to a MQTT server over TCP" do
    client_id = generate_client_id()

    _server_port = MQTT.Test.Server.start!()
    tracer_port = MQTT.Test.Tracer.start!(client_id)

    {:ok, _client_pid} = MQTT.Client.connect(@ip_address, client_id)

    assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, client_id})
  end

  defp generate_client_id do
    @client_id_byte_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end
end
