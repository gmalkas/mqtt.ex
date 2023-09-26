defmodule MQTT.ClientTest do
  use ExUnit.Case, async: false

  alias MQTT.Packet

  @client_id_byte_size 12
  @ip_address "127.0.0.1"

  setup_all do
    server_port = MQTT.Test.Server.start!()

    on_exit(fn ->
      MQTT.Test.Server.stop(server_port)
    end)

    :ok
  end

  describe "connect/3" do
    test "connects to a MQTT server over TCP" do
      {:ok, conn, tracer_port} = connect()

      assert :connecting = conn.state
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, conn.client_id})
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})
      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.connect_reason_code
      assert :connected = conn.state
    end
  end

  describe "subscribe/2" do
    test "sends a SUBSCRIBE packet with the topic filters" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      on_exit(fn ->
        MQTT.Test.Tracer.stop(tracer_port)
      end)

      topic_filter = "/my/topic"

      assert {:ok, conn} = MQTT.Client.subscribe(conn, [topic_filter])

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:subscribe, conn.client_id, topic_filter}
             )

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:suback, conn.client_id}
             )

      expected_reason_code = :granted_qos_0

      assert {:ok, %Packet.Suback{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert [^expected_reason_code] = packet.payload.reason_codes
      assert 0 = MapSet.size(conn.packet_identifiers)
    end
  end

  describe "publish/2" do
    test "sends a PUBLISH packet with the application message" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      on_exit(fn ->
        MQTT.Test.Tracer.stop(tracer_port)
      end)

      topic = "/my/topic"
      payload = "Hello world!"

      assert {:ok, conn} = MQTT.Client.publish(conn, topic, payload, qos: 1)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:publish, conn.client_id, topic}
             )

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:puback, conn.client_id}
             )

      assert {:ok, %Packet.Puback{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.reason_code
      assert 0 = MapSet.size(conn.packet_identifiers)
    end
  end

  defp connect(client_id \\ generate_client_id()) do
    tracer_port = MQTT.Test.Tracer.start!(client_id)

    on_exit(fn ->
      MQTT.Test.Tracer.stop(tracer_port)
    end)

    {:ok, conn} = MQTT.Client.connect(@ip_address, client_id)

    {:ok, conn, tracer_port}
  end

  defp connect_and_wait_for_connack(client_id \\ generate_client_id()) do
    {:ok, conn, tracer_port} = connect(client_id)

    assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, client_id})
    assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, client_id})
    assert {:ok, %Packet.Connack{}, conn} = MQTT.Client.read_next_packet(conn)

    {:ok, conn, tracer_port}
  end

  defp generate_client_id do
    @client_id_byte_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end
end
