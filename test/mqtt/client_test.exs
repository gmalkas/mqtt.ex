defmodule MQTT.ClientTest do
  use ExUnit.Case, async: false

  import MQTT.Test.Utils

  alias MQTT.{Packet, PacketBuilder, TransportError}
  alias MQTT.ClientSession, as: Session
  alias MQTT.ClientConn, as: Conn

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
      assert :success = packet.reason_code
      assert :connected = conn.state
    end

    test "connects to a MQTT server over IPv6" do
      {:ok, conn, tracer_port} = connect(endpoint: "::1", transport_opts: [inet6: true])

      assert :connecting = conn.state
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, conn.client_id})
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})
      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.reason_code
      assert :connected = conn.state
    end

    test "connects to a MQTT server over TLS" do
      {:ok, conn, tracer_port} =
        connect(
          endpoint: "localhost",
          transport: MQTT.Transport.TLS,
          transport_opts: [cacerts: [], verify_fun: {&verify_cert/3, nil}]
        )

      assert :connecting = conn.state
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, conn.client_id})
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})
      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.reason_code
      assert :connected = conn.state
    end

    test "connects to a MQTT server over websocket" do
      {:ok, conn, tracer_port} =
        connect(
          endpoint: {"localhost", 8866},
          transport: MQTT.Transport.Websocket,
          transport_opts: [path: "/mqtt"]
        )

      assert :connecting = conn.state
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, conn.client_id})
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})
      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.reason_code
      assert :connected = conn.state
    end

    test "supports receiving client ID from server" do
      {:ok, conn} = connect(client_id: nil, tracer?: false)

      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.reason_code
      refute is_nil(packet.properties.assigned_client_identifier)
      assert packet.properties.assigned_client_identifier == conn.client_id
      assert :connected = conn.state
    end

    test "supports username/password authentication" do
      user_name = "mqttex_basic"

      {:ok, conn, tracer_port} = connect(user_name: user_name, password: "password")

      assert :connecting = conn.state
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, conn.client_id, user_name})
      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})
      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert :success = packet.reason_code
      assert :connected = conn.state
    end

    test "supports setting a will message" do
      will_topic = "will_topic"
      will_payload = "will_payload"

      # The "watcher" connection which we use to test that the will message
      # was correctly specified by the client, cannot itself be traced as only
      # one VerneMQ tracer process can exist at a time.
      {:ok, watcher_conn} = connect(tracer?: false)

      # This read could lead to the test being flaky as we depend on the server
      # replying before the read timeout.
      assert {:ok, %Packet.Connack{}, watcher_conn} = MQTT.Client.read_next_packet(watcher_conn)

      assert {:ok, watcher_conn} = MQTT.Client.subscribe(watcher_conn, [will_topic])
      assert {:ok, %Packet.Suback{}, watcher_conn} = MQTT.Client.read_next_packet(watcher_conn)

      {:ok, conn, tracer_port} = connect(will_message: {will_topic, will_payload})

      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})

      assert {:ok, _conn} = MQTT.Client.disconnect(conn, :disconnect_with_will_message)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:disconnect, conn.client_id}
             )

      assert {:ok, %Packet.Publish{} = packet, _watcher_conn} =
               MQTT.Client.read_next_packet(watcher_conn)

      assert will_topic == packet.topic_name
      assert will_payload == packet.payload.data
    end
  end

  describe "subscribe/2" do
    test "sends a SUBSCRIBE packet with the topic filters and options" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      topic_filters = [
        "/my/topic",
        {"/some/other/topic", max_qos: 1, no_local?: true, retain_as_published?: true}
      ]

      assert {:ok, conn} = MQTT.Client.subscribe(conn, topic_filters)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:subscribe, conn.client_id, topic_filters}
             )

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:suback, conn.client_id}
             )

      assert {:ok, %Packet.Suback{} = packet, conn} = MQTT.Client.read_next_packet(conn)
      assert [:granted_qos_0, :granted_qos_1] = packet.payload.reason_codes
      refute Session.has_packet_identifier?(conn.session, packet.packet_identifier)
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
      refute Session.has_packet_identifier?(conn.session, packet.packet_identifier)
    end
  end

  describe "reconnect/1" do
    test "re-sends unacknowledged PUBLISH packets with QoS > 0" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      topic = "/my/topic"
      payload = "Hello world!"

      assert {:ok, conn} = MQTT.Client.publish(conn, topic, payload, qos: 1)

      assert {:ok, conn} = MQTT.Client.disconnect(conn)

      assert {:ok, conn} = MQTT.Client.reconnect(conn)

      assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})

      assert {:ok, %Packet.Connack{} = packet, conn} = MQTT.Client.read_next_packet(conn)

      # This test is dependent on timing as the server may or may have not
      # sent the PUBACK packet before we disconnected. If it did, it will have
      # no session when we reconnect, so we cannot expect the session to be
      # present.
      #
      # To make the test reliable, we test different things depending on the
      # state of the session on the server.
      #
      # If the session is present, we test that we republish the QoS 1 message.
      # If it is not, we test that we destroy the session on our side.

      if packet.flags.session_present? do
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
        assert 0 = Session.unacknowledged_message_count(conn.session)
      else
        refute MQTT.Test.Tracer.wait_for_trace(
                 tracer_port,
                 {:publish, conn.client_id, topic}
               )

        assert 0 = Session.unacknowledged_message_count(conn.session)
      end
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
      refute Session.has_packet_identifier?(conn.session, packet.packet_identifier)
    end
  end

  describe "disconnect/2" do
    test "sends a DISCONNECT packet" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      assert {:ok, conn} = MQTT.Client.disconnect(conn, :normal_disconnection)

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

    test "supports retained messages" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      topic = random_topic()
      application_message = "Hello world!"

      assert {:ok, conn} = MQTT.Client.publish(conn, topic, application_message, retain?: true)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:publish, conn.client_id, topic}
             )

      assert {:ok, conn} = MQTT.Client.subscribe(conn, [topic])

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:suback, conn.client_id}
             )

      assert {:ok, %Packet.Suback{}, conn} = MQTT.Client.read_next_packet(conn)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:send, :publish, conn.client_id, topic}
             )

      assert {:ok, %Packet.Publish{} = packet, _conn} = MQTT.Client.read_next_packet(conn)
      assert application_message == packet.payload.data
      assert packet.flags.retain?
    end

    test "supports Retain As Published" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      topic = random_topic()
      application_message = "Hello world!"

      assert {:ok, conn} = MQTT.Client.subscribe(conn, [{topic, [retain_as_published?: true]}])

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:suback, conn.client_id}
             )

      assert {:ok, %Packet.Suback{}, conn} = MQTT.Client.read_next_packet(conn)

      assert {:ok, conn} = MQTT.Client.publish(conn, topic, application_message, retain?: true)

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:publish, conn.client_id, topic}
             )

      assert MQTT.Test.Tracer.wait_for_trace(
               tracer_port,
               {:send, :publish, conn.client_id, topic}
             )

      assert {:ok, %Packet.Publish{} = packet, _conn} = MQTT.Client.read_next_packet(conn)
      assert application_message == packet.payload.data
      assert packet.flags.retain?
    end

    test "supports No Local" do
      {:ok, conn, tracer_port} = connect_and_wait_for_connack()

      topic = random_topic()
      application_message = "Hello world!"

      assert {:ok, conn} = MQTT.Client.subscribe(conn, [{topic, [no_local?: true]}])

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

      assert {:error, %TransportError{reason: :timeout}} = MQTT.Client.read_next_packet(conn)
    end
  end

  test "supports topic aliases" do
    {:ok, conn, tracer_port} = connect_and_wait_for_connack()

    # VerneMQ does not specify the `topic_alias_maximum` property despite
    # supporting topic aliases, so to test this we hardcode it to something > 0.
    conn = Conn.set_topic_alias_maximum(conn, 5)

    topic = "/my/topic"
    application_message = "Hello world!"

    assert {:ok, conn} = MQTT.Client.publish(conn, topic, application_message)

    assert MQTT.Test.Tracer.wait_for_trace(
             tracer_port,
             {:publish, conn.client_id, topic}
           )

    assert {:ok, conn} = MQTT.Client.publish(conn, topic, application_message, qos: 1)

    assert {:ok, topic_alias} = Conn.fetch_topic_alias(conn, topic)

    assert MQTT.Test.Tracer.wait_for_trace(
             tracer_port,
             {:publish, conn.client_id, "", topic_alias}
           )

    assert MQTT.Test.Tracer.wait_for_trace(
             tracer_port,
             {:puback, conn.client_id}
           )

    assert {:ok, %Packet.Puback{} = packet, _conn} = MQTT.Client.read_next_packet(conn)
    assert :success = packet.reason_code
  end

  test "supports Keep Alive" do
    {:ok, conn, tracer_port} = connect_and_wait_for_connack(keep_alive: 1)

    :timer.sleep(1000)

    {:ok, conn} = MQTT.Client.tick(conn)

    assert MQTT.Test.Tracer.wait_for_trace(
             tracer_port,
             {:pingreq, conn.client_id}
           )

    assert MQTT.Test.Tracer.wait_for_trace(
             tracer_port,
             {:pingresp, conn.client_id}
           )
  end

  test "supports QoS 2" do
    {:ok, conn, tracer_port} = connect_and_wait_for_connack()

    topic = "/my/topic"
    payload = "Hello world!"

    assert {:ok, conn} = MQTT.Client.publish(conn, topic, payload, qos: 2)

    assert MQTT.Test.Tracer.wait_for_trace(
             tracer_port,
             {:publish, conn.client_id, topic}
           )

    assert MQTT.Test.Tracer.wait_for_trace(
             tracer_port,
             {:pubrec, conn.client_id}
           )

    assert {:ok, %Packet.Pubrec{} = pubrec_packet, conn} = MQTT.Client.read_next_packet(conn)

    pubrel_packet = PacketBuilder.Pubrel.new(pubrec_packet.packet_identifier)
    assert {:ok, conn} = MQTT.Client.send_packet(conn, pubrel_packet)

    assert MQTT.Test.Tracer.wait_for_trace(
             tracer_port,
             {:pubcomp, conn.client_id}
           )

    assert {:ok, %Packet.Pubcomp{} = pubcomp_packet, _conn} = MQTT.Client.read_next_packet(conn)
    assert pubrec_packet.packet_identifier == pubcomp_packet.packet_identifier
  end

  test "respects Maximum Packet Size" do
    fake_packets = [
      PacketBuilder.Connack.new()
      |> PacketBuilder.Connack.with_maximum_packet_size(10)
    ]

    {:ok, server_pid} = MQTT.Test.FakeServer.start_link()
    {:ok, server_port} = MQTT.Test.FakeServer.accept_loop(server_pid, fake_packets)

    {:ok, conn} = connect(endpoint: {@ip_address, server_port}, tracer?: false)
    {:ok, conn} = MQTT.Client.set_mode(conn, :active)

    {:ok, conn, _} =
      receive do
        message ->
          MQTT.Client.data_received(conn, message)
      end

    topic = "/my/topic"
    payload = "Hello world!"

    assert {:error, :packet_too_large} = MQTT.Client.publish(conn, topic, payload, qos: 1)
  end

  defp connect(options \\ []) do
    client_id = Keyword.get_lazy(options, :client_id, &generate_client_id/0)
    tracer? = Keyword.get(options, :tracer?, true)
    endpoint = Keyword.get(options, :endpoint, @ip_address)

    connect_options =
      options
      |> Keyword.take([
        :keep_alive,
        :user_name,
        :password,
        :will_message,
        :transport,
        :transport_opts
      ])
      |> Keyword.put(:client_id, client_id)

    if tracer? do
      tracer_port = MQTT.Test.Tracer.start!(client_id)
      {:ok, conn} = MQTT.Client.connect(endpoint, connect_options)

      {:ok, conn, tracer_port}
    else
      MQTT.Client.connect(endpoint, connect_options)
    end
  end

  defp connect_and_wait_for_connack(options \\ []) do
    {:ok, conn, tracer_port} = connect(options)

    assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connect, conn.client_id})
    assert MQTT.Test.Tracer.wait_for_trace(tracer_port, {:connack, conn.client_id})
    assert {:ok, %Packet.Connack{}, conn} = MQTT.Client.read_next_packet(conn)

    {:ok, conn, tracer_port}
  end
end
