defmodule MQTT.Test.Tracer do
  require Logger

  @exec_path Path.join(File.cwd!(), "vendor/vernemq/_build/default/rel/vernemq/bin/vmq-admin")
  @port_read_timeout_ms 1500

  def start!(client_id) do
    port = open_port(client_id)

    wait_until_ready(port, client_id)

    port
  end

  def wait_for_trace(port, {:connect, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT RECV: CID: "#{client_id}" CONNECT))
  end

  def wait_for_trace(port, {:connect, client_id, user_name}) do
    read_from_port_until_trace(
      port,
      ~r/MQTT RECV: CID: "#{Regex.escape(client_id)}" CONNECT.*, u: #{Regex.escape(user_name)}/
    )
  end

  def wait_for_trace(port, {:subscribe, client_id, topic_filter}) do
    read_from_port_until_trace(
      port,
      ~r/MQTT RECV: CID: "#{Regex.escape(client_id)}" SUBSCRIBE.*\n.*\n\s+t: "#{Regex.escape(topic_filter)}"/
    )
  end

  def wait_for_trace(port, {:unsubscribe, client_id, topic_filter}) do
    read_from_port_until_trace(
      port,
      ~r/MQTT RECV: CID: "#{Regex.escape(client_id)}" UNSUBSCRIBE.*\n\s+t: "#{Regex.escape(topic_filter)}"/
    )
  end

  def wait_for_trace(port, {:connack, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT SEND: CID: "#{client_id}" CONNACK))
  end

  def wait_for_trace(port, {:suback, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT SEND: CID: "#{client_id}" SUBACK))
  end

  def wait_for_trace(port, {:unsuback, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT SEND: CID: "#{client_id}" UNSUBACK))
  end

  def wait_for_trace(port, {:publish, client_id, topic_name}) do
    read_from_port_until_trace(
      port,
      ~r/MQTT RECV: CID: "#{Regex.escape(client_id)}" PUBLISH.*"#{Regex.escape(topic_name)}"/
    )
  end

  def wait_for_trace(port, {:publish, client_id, topic_name, topic_alias}) do
    read_from_port_until_trace(
      port,
      ~r/MQTT RECV: CID: "#{Regex.escape(client_id)}" PUBLISH.*"#{Regex.escape(topic_name)}"\).*\n.*\n.*topic_alias => #{topic_alias}/
    )
  end

  def wait_for_trace(port, {send_or_recv, :publish, client_id, topic_name}) do
    read_from_port_until_trace(
      port,
      ~r/MQTT #{format_trace_type(send_or_recv)}: CID: "#{Regex.escape(client_id)}" PUBLISH.*"#{Regex.escape(topic_name)}"/
    )
  end

  def wait_for_trace(port, {:puback, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT SEND: CID: "#{client_id}" PUBACK))
  end

  def wait_for_trace(port, {:disconnect, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT RECV: CID: "#{client_id}" DISCONNECT))
  end

  def wait_for_trace(port, {:pingreq, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT RECV: CID: "#{client_id}" PINGREQ))
  end

  def wait_for_trace(port, {:pingresp, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT SEND: CID: "#{client_id}" PINGRESP))
  end

  defp open_port(client_id) do
    Port.open(
      {:spawn_executable, @exec_path},
      [:binary, :exit_status, args: ["trace", "client", "client-id=#{client_id}"]]
    )
  end

  defp wait_until_ready(port, client_id) do
    true = read_from_port_until_trace(port, ~s(No sessions found for client "#{client_id}"))
  end

  defp read_from_port_until_trace(port, trace, buffer \\ "") do
    receive do
      {^port, {:data, data}} ->
        Logger.debug("#{inspect(port)}: data=#{inspect(data)}")

        buffer = buffer <> data

        if match_trace?(buffer, trace) do
          true
        else
          read_from_port_until_trace(port, trace, buffer)
        end
    after
      @port_read_timeout_ms ->
        false
    end
  end

  defp match_trace?(data, trace) when is_binary(trace) do
    String.contains?(data, trace)
  end

  defp match_trace?(data, %Regex{} = trace) do
    String.match?(data, trace)
  end

  defp format_trace_type(:send), do: "SEND"
  defp format_trace_type(:recv), do: "RECV"
end
