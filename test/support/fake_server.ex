defmodule MQTT.Test.FakeServer do
  use GenServer

  require Logger

  alias __MODULE__, as: State
  alias MQTT.{Packet, PacketBuilder}

  defstruct [:listen_socket, :port, :socket]

  # API

  def accept_loop(pid) do
    {:ok, port} = GenServer.call(pid, :port)

    :ok = GenServer.cast(pid, :accept_loop)

    {:ok, port}
  end

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def terminate(pid) do
    GenServer.call(pid, :terminate)
  end

  # CALLBACKS

  @impl true
  def init(_args) do
    {:ok, nil, {:continue, :listen}}
  end

  @impl true
  def handle_continue(:listen, nil) do
    case do_listen() do
      {:ok, listen_socket} ->
        {:ok, port} = :inet.port(listen_socket)

        Logger.debug("pid=#{inspect(self())}, port=#{port}, event=listening")

        {:noreply, %State{listen_socket: listen_socket, port: port}}
    end
  end

  @impl true
  def handle_call(:port, _from, %State{} = state) do
    {:reply, {:ok, state.port}, state}
  end

  @impl true
  def handle_call(:terminate, _from, %State{} = state) do
    close_socket(state.socket)

    {:reply, :ok, %State{state | socket: nil}}
  end

  @impl true
  def handle_cast(:accept_loop, %State{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        {:noreply, %State{state | socket: socket}}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, %State{socket: socket} = state) do
    :inet.setopts(socket, active: :once)

    handle_data(socket, data)

    {:noreply, state}
  end

  # HELPERS

  defp do_listen do
    :gen_tcp.listen(0, active: :once, mode: :binary)
  end

  defp close_socket(nil), do: :ok
  defp close_socket(socket), do: :gen_tcp.close(socket)

  defp handle_data(socket, _data) do
    packet =
      PacketBuilder.Connack.new()
      |> Packet.Connack.encode!()

    :ok = :gen_tcp.send(socket, packet)
  end
end
