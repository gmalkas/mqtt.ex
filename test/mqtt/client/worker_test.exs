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

defmodule MQTT.Client.WorkerTest do
  use ExUnit.Case, async: false

  import MQTT.Test.Utils

  alias MQTT.Packet

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
      MQTT.Client.Worker.start_link(
        client_id: generate_client_id(),
        endpoint: @ip_address,
        handler: {MockHandler, self()}
      )

    assert_receive {:connected, %Packet.Connack{}}
  end

  test "supports websockets" do
    {:ok, _pid} =
      MQTT.Client.Worker.start_link(
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
      MQTT.Client.Worker.start_link(
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
      MQTT.Client.Worker.start_link(
        client_id: generate_client_id(),
        endpoint: @ip_address,
        handler: {MockHandler, self()}
      )

    topic_filter = "/my/topic"

    assert_receive {:connected, %Packet.Connack{}}

    assert :ok = MQTT.Client.Worker.subscribe(pid, [topic_filter])
    assert_receive {:subscription, %Packet.Suback{}}
  end

  test "calls the event handler for publish events" do
    {:ok, pid} =
      MQTT.Client.Worker.start_link(
        client_id: generate_client_id(),
        endpoint: @ip_address,
        handler: {MockHandler, self()}
      )

    topic_filter = "/my/topic"
    payload = "Hello world!"

    assert_receive {:connected, %Packet.Connack{}}
    :ok = MQTT.Client.Worker.subscribe(pid, [topic_filter])

    assert :ok = MQTT.Client.Worker.publish(pid, topic_filter, payload)
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
        MQTT.Client.Worker.start_link(
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
end
