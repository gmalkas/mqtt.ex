defmodule MQTT.Test.Server do
  require Logger

  @exec_path Path.join(File.cwd!(), "vendor/vernemq/_build/default/rel/vernemq/bin/vernemq")
  @port_read_timeout_ms 5000
  @server_ready_message "(VerneMQ@127.0.0.1)1>"

  def start! do
    port = open_port()

    :ok = read_from_port_until_ready(port)

    Task.start(fn ->
      read_from_port_for_logging(port)
    end)

    port
  end

  def stop!(port) do
    if !Port.close(port) do
      raise "Unable to close Port for MQTT Server!"
    end
  end

  defp open_port, do: Port.open({:spawn_executable, @exec_path}, args: ["console"])

  defp read_from_port_until_ready(port, buffer \\ "") do
    receive do
      {^port, {:data, data}} ->
        buffer = buffer <> to_string(data)

        if String.contains?(buffer, @server_ready_message) do
          :ok
        else
          read_from_port_until_ready(port, buffer)
        end
    after
      @port_read_timeout_ms ->
        :error
    end
  end

  defp read_from_port_for_logging(port, buffer \\ "") do
    receive do
      {^port, {:data, data}} ->
        buffer = buffer <> to_string(data)

        {lines, [buffer]} =
          buffer
          |> String.split("\n")
          |> Enum.split(-1)

        Enum.each(lines, &Logger.debug/1)

        read_from_port_for_logging(port, buffer)
    end
  end
end
