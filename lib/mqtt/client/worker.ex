defmodule MQTT.Client.Worker do
  use GenServer

  require Logger

  alias MQTT.{Client, Packet}
  alias MQTT.ClientConn, as: Conn
  alias __MODULE__, as: State

  defstruct [:conn, :handler, :handler_state]

  # API

  def publish(pid, topic_name, payload, options \\ []) do
    GenServer.call(pid, {:publish, topic_name, payload, options})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def subscribe(pid, topic_filters) do
    GenServer.call(pid, {:subscribe, topic_filters})
  end

  # CALLBACKS

  @impl true
  def init(args) do
    {:ok, args, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, args) do
    endpoint = Keyword.get(args, :endpoint)
    client_id = Keyword.get(args, :client_id)

    {handler_mod, handler_opts} = Keyword.get(args, :handler)
    {:ok, handler_state} = handler_mod.init(handler_opts)

    {:ok, conn} = Client.connect(endpoint, client_id, args)
    {:ok, conn} = Client.set_mode(conn, :active)

    {:noreply, %State{conn: conn, handler: handler_mod, handler_state: handler_state}}
  end

  @impl true
  def handle_call({:publish, topic_name, payload, options}, _from, state) do
    case Client.publish(state.conn, topic_name, payload, options) do
      {:ok, conn} ->
        {:reply, :ok, %State{state | conn: conn}}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, topic_filters}, _from, state) do
    case Client.subscribe(state.conn, topic_filters) do
      {:ok, conn} ->
        {:reply, :ok, %State{state | conn: conn}}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_cast({:publish, topic_name, payload, options}, state) do
    case Client.publish(state.conn, topic_name, payload, options) do
      {:ok, conn} ->
        {:noreply, %State{state | conn: conn}}

      {:error, _error} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:subscribe, topic_filters}, state) do
    case Client.subscribe(state.conn, topic_filters) do
      {:ok, conn} ->
        {:noreply, %State{state | conn: conn}}

      {:error, _error} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:keep_alive, %State{conn: %Conn{state: :connected}} = state) do
    # If Keep Alive is non-zero and in the absence of sending any other MQTT
    # Control Packets, the Client MUST send a PINGREQ packet [MQTT-3.1.2-20].

    case Client.ping(state.conn) do
      {:ok, conn} ->
        {:noreply, %State{state | conn: conn}}

      {:error, error} ->
        next_state = handle_error(state, error)
        {:noreply, next_state}
    end
  end

  @impl true
  def handle_info(:keep_alive, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:ping_timeout, %State{conn: %Conn{state: :connected}} = state) do
    next_state = handle_error(state, %MQTT.TransportError{reason: :timeout})

    {:noreply, next_state}
  end

  @impl true
  def handle_info(:ping_timeout, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(message, state) do
    case Client.data_received(state.conn, message) do
      {:ok, conn, packets} ->
        Logger.debug(
          "pid=#{inspect(self())}, event=received_packets, packets=#{inspect(packets)}"
        )

        {:ok, conn} = Client.set_mode(conn, :active)

        next_state = handle_packets(state, packets)

        {:noreply, %State{next_state | conn: conn}}

      {:ok, :closed} ->
        {:ok, conn} = Conn.disconnected(state.conn)

        next_state = emit_event(state, {:disconnected, :transport_closed})

        {:noreply, %State{next_state | conn: conn}}
    end
  end

  # HELPERS

  defp handle_error(state, %MQTT.TransportError{} = error) do
    {:ok, conn} = Client.disconnect!(state.conn)

    emit_event(%State{state | conn: conn}, {:disconnected, error})
  end

  defp handle_packets(state, packets) do
    Enum.reduce(packets, state, &handle_packet/2)
  end

  defp handle_packet(packet, state) do
    event =
      case packet do
        %Packet.Connack{} ->
          {:connected, packet}

        %Packet.Suback{} ->
          {:subscription, packet}

        %Packet.Publish{} ->
          {:publish, packet}

        %Packet.Pingresp{} ->
          {:pong, packet}
      end

    emit_event(state, event)
  end

  defp emit_event(state, event) do
    {next_handler_state, actions} = dispatch_event(state.handler, state.handler_state, event)

    dispatch_actions(actions)

    %State{state | handler_state: next_handler_state}
  end

  defp dispatch_event(handler, handler_state, event) do
    case handler.handle_events([event], handler_state) do
      {:ok, next_handler_state, actions} ->
        {next_handler_state, actions}
    end
  end

  defp dispatch_actions(actions), do: Enum.each(actions, &GenServer.cast(self(), &1))
end
