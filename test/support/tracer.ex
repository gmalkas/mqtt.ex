defmodule MQTT.Test.Tracer do
  require Logger

  @exec_path Path.join(File.cwd!(), "vendor/vernemq/_build/default/rel/vernemq/bin/vmq-admin")
  @port_read_timeout_ms 1500

  def start!(client_id) do
    port = open_port(client_id)

    wait_until_ready(port, client_id)

    port
  end

  def stop!(port) do
    if !Port.close(port) do
      raise "Unable to close Port for MQTT Server!"
    end
  end

  def wait_for_trace(port, {:connect, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT RECV: CID: "#{client_id}" CONNECT))
  end

  def wait_for_trace(port, {:connack, client_id}) do
    read_from_port_until_trace(port, ~s(MQTT SEND: CID: "#{client_id}" CONNACK))
  end

  defp open_port(client_id) do
    Port.open({:spawn_executable, @exec_path},
      args: ["trace", "client", "client-id=#{client_id}"]
    )
  end

  defp wait_until_ready(port, client_id) do
    true = read_from_port_until_trace(port, ~s(No sessions found for client "#{client_id}"))
  end

  defp read_from_port_until_trace(port, trace, buffer \\ "") do
    receive do
      {^port, {:data, data}} ->
        Logger.debug("#{inspect(port)}: data=#{inspect(data)}")

        buffer = buffer <> to_string(data)

        if String.contains?(buffer, trace) do
          true
        else
          read_from_port_until_trace(port, trace, buffer)
        end
    after
      @port_read_timeout_ms ->
        false
    end
  end
end
