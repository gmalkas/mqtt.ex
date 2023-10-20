defmodule MockHandler do
  def init(pid) do
    {:ok, pid}
  end

  def handle_events(events, pid) do
    Enum.each(events, &send(pid, &1))

    {:ok, pid}
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
    assert_receive {:subscription, %Packet.Suback{}}, 250
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
    assert_receive {:publish, %Packet.Publish{} = packet}, 1000

    assert topic_filter == packet.topic_name
    assert payload == packet.payload.data
  end
end
