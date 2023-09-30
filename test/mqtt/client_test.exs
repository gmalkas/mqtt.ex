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

    test "supports username/password authentication" do
      user_name = "mqttex_basic"

      {:ok, conn, tracer_port} = connect(user_name: user_name, password: "password")

      assert :connecting = conn.state
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, conn.client_id, user_name})
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})
      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.connect_reason_code
      assert :connected = conn.state
    end
  end

  describe "subscribe/2" do
    test "sends a SUBSCRIBE packet with the topic filters" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

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

  describe "unsubscribe/2" do
    test "sends a UNSUBSCRIBE packet with the topic filters" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      topic_filter_1 = "/my/topic"

      assert {:ok, conn} = MQTT.Client.subscribe(conn, [topic_filter_1])

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:suback, conn.client_id}
             )

      assert {:ok, %Packet.Suback{}, conn} = MQTT.Client.read_next_packet(conn)

      assert {:ok, conn} = MQTT.Client.unsubscribe(conn, [topic_filter_1])

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:unsubscribe, conn.client_id, topic_filter_1}
             )

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:unsuback, conn.client_id}
             )

      expected_reason_codes = [:success]

      assert {:ok, %Packet.Unsuback{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert ^expected_reason_codes = packet.payload.reason_codes
      assert 0 = MapSet.size(conn.packet_identifiers)
    end
  end

  describe "publish/2" do
    test "sends a PUBLISH packet with the application message" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

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

  describe "disconnect/1" do
    test "sends a DISCONNECT packet" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      assert {:ok, conn} = MQTT.Client.disconnect(conn)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:disconnect, conn.client_id}
             )

      assert :disconnected = conn.state
    end
  end

  describe "ping/1" do
    test "sends a PINGREQ packet" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      assert {:ok, conn} = MQTT.Client.ping(conn)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:pingreq, conn.client_id}
             )

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:pingresp, conn.client_id}
             )

      assert {:ok, %Packet.Pingresp{}, _conn} = MQTT.Client.read_next_packet(conn)
    end
  end

  describe "subscribing to a topic and receiving application messages" do
    test "reads PUBLISH packets from the server after subscribing" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      topic = "/my/topic"
      application_message = "Hello world!"

      assert {:ok, conn} = MQTT.Client.subscribe(conn, [topic])

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:suback, conn.client_id}
             )

      assert {:ok, %Packet.Suback{}, conn} = MQTT.Client.read_next_packet(conn)

      assert {:ok, conn} = MQTT.Client.publish(conn, topic, application_message)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:publish, conn.client_id, topic}
             )

      assert {:ok, %Packet.Publish{} = packet, _conn} = MQTT.Client.read_next_packet(conn)
      assert application_message == packet.payload.data
    end
  end

  defp connect(options \\ []) do
    client_id = Keyword.get_lazy(options, :client_id, &generate_client_id/0)
    tracer? = Keyword.get(options, :tracer?, true)
    connect_options = Keyword.take(options, [:user_name, :password])

    if tracer? do
      tracer_port = MQTT.Test.Tracer.start!(client_id)
      {:ok, conn} = MQTT.Client.connect(@ip_address, client_id, connect_options)

      {:ok, conn, tracer_port}
    else
      MQTT.Client.connect(@ip_address, client_id, connect_options)
    end
  end

  defp connect_and_wait_for_connack(options \\ []) do
    {:ok, conn, tracer_port} = connect(options)

    assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, conn.client_id})
    assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})
    assert {:ok, %Packet.Connack{}, conn} = MQTT.Client.read_next_packet(conn)

    {:ok, conn, tracer_port}
  end

  defp generate_client_id do
    @client_id_byte_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end
end
