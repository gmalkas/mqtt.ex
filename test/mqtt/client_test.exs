defmodule MQTT.ClientTest do
  use ExUnit.Case, async: false

  alias MQTT.Packet

  @client_id_byte_size 12
  @ip_address "127.0.0.1"

  describe "connect/3" do
    test "connects to a MQTT server over TCP and handles CONNACK" do
      client_id = generate_client_id()

      _server_port = MQTT.Test.Server.start!()
      tracer_port = MQTT.Test.Tracer.start!(client_id)

      {:ok, conn} = MQTT.Client.connect(@ip_address, client_id)

      assert :connecting = conn.state
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, client_id})
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, client_id})
      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.connect_reason_code
      assert :connected = conn.state
    end
  end

  defp generate_client_id do
    @client_id_byte_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end
end
