defmodule MockHandler do
  def init(args) do
    {:ok, args}
  end

  def handle_events(events, state) do
    {pid, event_actions} =
      case state do
        pid when is_pid(pid) ->
          {pid, []}

        [pid, event_actions] ->
          {pid, event_actions}
      end

    actions =
      Enum.reduce(events, [], fn event, action_acc ->
        send(pid, event)

        Enum.reduce(event_actions, action_acc, fn event_action, acc ->
          case {event, event_action} do
            {{event_type, _packet}, {event_type, action}} ->
              [action | acc]

            _ ->
              acc
          end
        end)
      end)

    {:ok, state, Enum.reverse(actions)}
  end
end

defmodule MQTT.Client.ConnectionTest do
  use ExUnit.Case, async: false

  import MQTT.Test.Utils

  alias MQTT.{Client.ReconnectStrategy, Packet, PacketBuilder}

  @ip_address "127.0.0.1"

  setup_all do
    server_port = MQTT.Test.Server.start!()

    on_exit(fn ->
      MQTT.Test.Server.stop(server_port)
    end)

    :ok
  end

  test "calls the event handler for connection events" do
    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: @ip_address,
        handler: {MockHandler, self()}
      )

    assert_receive {:connected, %Packet.Connack{}}
  end

  test "supports websockets" do
    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: {@ip_address, 8866},
        transport: MQTT.Transport.Websocket,
        transport_opts: [path: "/mqtt"],
        handler: {MockHandler, self()}
      )

    assert_receive {:connected, %Packet.Connack{}}
  end

  test "supports TLS" do
    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: {@ip_address, 8883},
        transport: MQTT.Transport.TLS,
        transport_opts: [cacerts: [], verify_fun: {&verify_cert/3, nil}],
        handler: {MockHandler, self()}
      )

    assert_receive {:connected, %Packet.Connack{}}
  end

  test "calls the event handler for subscription events" do
    {:ok, pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: @ip_address,
        handler: {MockHandler, self()}
      )

    topic_filter = "/my/topic"

    assert_receive {:connected, %Packet.Connack{}}

    assert :ok = MQTT.Client.Connection.subscribe(pid, [topic_filter])
    assert_receive {:subscription, %Packet.Suback{}}
  end

  test "calls the event handler for publish events" do
    {:ok, pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: @ip_address,
        handler: {MockHandler, self()}
      )

    topic_filter = "/my/topic"
    payload = "Hello world!"

    assert_receive {:connected, %Packet.Connack{}}
    :ok = MQTT.Client.Connection.subscribe(pid, [topic_filter])

    assert :ok = MQTT.Client.Connection.publish(pid, topic_filter, payload)
    assert_receive {:publish, %Packet.Publish{} = packet}

    assert topic_filter == packet.topic_name
    assert payload == packet.payload.data
  end

  describe "handler actions" do
    test "supports subscribing and publishing" do
      topic_filter = "/my/topic"
      payload = "Hello world!"

      event_actions = [
        {:connected, {:subscribe, [topic_filter]}},
        {:subscription, {:publish, topic_filter, payload, []}}
      ]

      {:ok, _pid} =
        MQTT.Client.Connection.start_link(
          client_id: generate_client_id(),
          endpoint: @ip_address,
          handler: {MockHandler, [self(), event_actions]}
        )

      assert_receive {:connected, %Packet.Connack{}}
      assert_receive {:publish, %Packet.Publish{} = packet}

      assert topic_filter == packet.topic_name
      assert payload == packet.payload.data
    end
  end

  test "uses keep alive to detect network issues" do
    {:ok, server_pid} = MQTT.Test.FakeServer.start_link()
    {:ok, server_port} = MQTT.Test.FakeServer.accept_loop(server_pid)

    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        keep_alive: 1,
        timeout: 100,
        endpoint: {@ip_address, server_port},
        handler: {MockHandler, self()}
      )

    assert_receive {:connected, %Packet.Connack{}}
    assert_receive {:disconnected, %MQTT.TransportError{reason: :timeout}}, 1_200
  end

  test "supports server redirection" do
    {:ok, alt_server_pid} = MQTT.Test.FakeServer.start_link()
    {:ok, alt_server_port} = MQTT.Test.FakeServer.accept_loop(alt_server_pid)

    connack_packet =
      PacketBuilder.Connack.new()
      |> PacketBuilder.Connack.with_server_redirection(
        :server_moved,
        "localhost:#{alt_server_port}"
      )

    {:ok, server_pid} = MQTT.Test.FakeServer.start_link()
    {:ok, server_port} = MQTT.Test.FakeServer.accept_loop(server_pid, [connack_packet])

    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: {@ip_address, server_port},
        handler: {MockHandler, self()}
      )

    assert_receive {:redirected, %Packet.Connack{}}
    assert_receive {:connected, %Packet.Connack{}}
    assert MQTT.Test.FakeServer.has_client?(alt_server_pid)
  end

  test "automatically reconnects when losing connection" do
    {:ok, server_pid} = MQTT.Test.FakeServer.start_link()
    {:ok, server_port} = MQTT.Test.FakeServer.accept_loop(server_pid)

    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: {@ip_address, server_port},
        handler: {MockHandler, self()},
        reconnect_strategy: ReconnectStrategy.ConstantBackoff.new(0)
      )

    assert_receive {:connected, %Packet.Connack{}}
    :ok = MQTT.Test.FakeServer.terminate(server_pid)

    assert_receive {:disconnected, :transport_closed}

    assert_receive {:connected, %Packet.Connack{}}
  end

  test "supports enhanced authentication flow" do
    authentication_method = "SCRAM-SHA-1"

    fake_packets = [
      PacketBuilder.Auth.new(:continue_authentication, authentication_method, "step2"),
      PacketBuilder.Connack.new()
      |> PacketBuilder.Connack.with_enhanced_authentication(authentication_method, "step4")
    ]

    {:ok, server_pid} = MQTT.Test.FakeServer.start_link()
    {:ok, server_port} = MQTT.Test.FakeServer.accept_loop(server_pid, fake_packets)

    event_actions = [
      {:auth, {:auth, :continue_authentication, authentication_method, "step3"}}
    ]

    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: {@ip_address, server_port},
        enhanced_authentication: {authentication_method, "myusername"},
        handler: {MockHandler, [self(), event_actions]}
      )

    assert_receive {:auth, %Packet.Auth{} = auth_packet}
    assert authentication_method == auth_packet.properties.authentication_method
    assert "step2" == auth_packet.properties.authentication_data

    assert_receive {:connected, %Packet.Connack{} = connack_packet}
    assert authentication_method == connack_packet.properties.authentication_method
    assert "step4" == connack_packet.properties.authentication_data
  end

  test "supports a connection timeout" do
    {:ok, server_pid} = MQTT.Test.FakeServer.start_link()
    {:ok, server_port} = MQTT.Test.FakeServer.accept_loop(server_pid, [])

    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: {@ip_address, server_port},
        handler: {MockHandler, self()},
        connect_timeout: 1
      )

    assert_receive {:error, %MQTT.TransportError{reason: :connect_timeout}}, 50
  end

  test "handles server-initiated disconnect" do
    fake_packets =
      [
        [
          PacketBuilder.Connack.new(),
          PacketBuilder.Disconnect.new(:server_busy)
        ]
      ]

    {:ok, server_pid} = MQTT.Test.FakeServer.start_link()
    {:ok, server_port} = MQTT.Test.FakeServer.accept_loop(server_pid, fake_packets)

    {:ok, _pid} =
      MQTT.Client.Connection.start_link(
        client_id: generate_client_id(),
        endpoint: {@ip_address, server_port},
        handler: {MockHandler, self()}
      )

    assert_receive {:connected, _}
    assert_receive {:disconnected, %Packet.Disconnect{reason_code: :server_busy}}
  end
end
