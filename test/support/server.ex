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

  def stop(port) do
    if !is_nil(Port.info(port)) do
      Port.close(port)
    end

    terminate_server_process()
  end

  defp open_port, do: Port.open({:spawn_executable, @exec_path}, args: ["console"])

  defp terminate_server_process do
    case System.cmd(@exec_path, ["stop"]) do
      {_stdout, 0} ->
        :ok

      {stdout, exit_status} ->
        if String.contains?(stdout, "Node is not running!") do
          :ok
        else
          Logger.warning(
            "Unable to terminate MQTT server: exit_status=#{exit_status}, stdout=#{stdout}"
          )

          :error
        end
    end
  end

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
