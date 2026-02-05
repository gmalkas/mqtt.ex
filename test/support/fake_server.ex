defmodule MQTT.Test.FakeServer do
  use GenServer

  require Logger

  alias __MODULE__, as: State
  alias MQTT.{Packet, PacketBuilder}

  defstruct [:listen_socket, :port, :socket, :packets, :reply_queue]

  # API

  def accept_loop(pid, packets \\ default_packets()) when is_list(packets) do
    {:ok, port} = GenServer.call(pid, :port)

    :ok = GenServer.cast(pid, {:accept_loop, packets})

    {:ok, port}
  end

  def has_client?(pid) do
    GenServer.call(pid, :has_client?)
  end

  def reply!(pid, packet) do
    GenServer.call(pid, {:reply, packet})
  end

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def terminate(pid) do
    GenServer.call(pid, :terminate)
  end

  # CALLBACKS

  @impl true
  def init(args) do
    {:ok, %State{port: Keyword.get(args, :port, 0)}, {:continue, :listen}}
  end

  @impl true
  def handle_continue(:listen, %State{} = state) do
    case do_listen(state.port) do
      {:ok, listen_socket} ->
        {:ok, port} = :inet.port(listen_socket)

        Logger.debug("pid=#{inspect(self())}, port=#{port}, event=listening")

        {:noreply, %State{listen_socket: listen_socket, port: port}}
    end
  end

  @impl true
  def handle_call(:has_client?, _from, %State{} = state) do
    {:reply, !is_nil(state.socket), state}
  end

  @impl true
  def handle_call(:port, _from, %State{} = state) do
    {:reply, {:ok, state.port}, state}
  end

  @impl true
  def handle_call({:reply, packet}, _from, %State{} = state) do
    send_reply!(state.socket, packet)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:terminate, _from, %State{} = state) do
    close_socket(state.socket)

    :ok = GenServer.cast(self(), {:accept_loop, state.packets})

    {:reply, :ok, %State{state | socket: nil}}
  end

  @impl true
  def handle_cast({:accept_loop, packets}, %State{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        {:noreply, %State{state | packets: packets, reply_queue: packets, socket: socket}}
    end
  end

  @impl true
  def handle_info({:tcp, socket, _data}, %State{socket: socket} = state) do
    :ok = :inet.setopts(socket, active: :once)

    next_state =
      case state.reply_queue do
        [packet_group | packets] when is_list(packet_group) ->
          Enum.each(packet_group, &send_reply!(socket, &1))

          %State{state | reply_queue: packets}

        [packet | packets] ->
          send_reply!(socket, packet)

          %State{state | reply_queue: packets}

        [] ->
          state
      end

    {:noreply, next_state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %State{socket: socket} = state) do
    {:noreply, %State{state | socket: nil}}
  end

  # HELPERS

  defp do_listen(port) do
    :gen_tcp.listen(port, active: :once, mode: :binary, reuseaddr: true)
  end

  defp close_socket(nil), do: :ok
  defp close_socket(socket), do: :gen_tcp.close(socket)

  defp send_reply!(socket, packet) do
    :ok = :gen_tcp.send(socket, Packet.encode!(packet))
  end

  defp default_packets, do: [PacketBuilder.Connack.new()]
end
