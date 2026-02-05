defmodule MQTT.Client.Connection do
  @moduledoc """
  """

  use GenServer

  require Logger

  alias MQTT.{Client, Error, Packet, TransportError}
  alias MQTT.ClientConn, as: Conn
  alias __MODULE__, as: State

  defstruct [:conn, :handler, :handler_state, :options]

  # API

  def publish(pid, topic_name, payload, options \\ []) do
    GenServer.call(pid, {:publish, topic_name, payload, options})
  end

  @doc """
  Creates a new connection to a given server.

  Creates a new connection struct and establishes the connection to the given
  server, identified by the given `endpoint`.

  ## Usage

  ## Mode

  ## TLS

  ## Extended Authentication

  ## Will Message
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def subscribe(pid, topic_filters) do
    GenServer.call(pid, {:subscribe, topic_filters})
  end

  def unsubscribe(pid, topic_filters) do
    GenServer.call(pid, {:unsubscribe, topic_filters})
  end

  # CALLBACKS

  @impl true
  def init(args) do
    {:ok, args, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, args) do
    try_to_connect(args)
  end

  @impl true
  def handle_call({:publish, topic_name, payload, options}, _from, state) do
    case Client.publish(state.conn, topic_name, payload, options) do
      {:ok, packet, conn} ->
        {:reply, {:ok, packet}, %State{state | conn: conn}}

      {:error, error} ->
        # TODO: Handle errors
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, topic_filters}, _from, state) do
    case Client.subscribe(state.conn, topic_filters) do
      {:ok, packet, conn} ->
        {:reply, {:ok, packet}, %State{state | conn: conn}}

      {:error, error} ->
        # TODO: Handle errors
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, topic_filters}, _from, state) do
    case Client.unsubscribe(state.conn, topic_filters) do
      {:ok, packet, conn} ->
        {:reply, {:ok, packet}, %State{state | conn: conn}}

      {:error, error} ->
        # TODO: Handle errors
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_cast({:auth, reason_code, authentication_method, authentication_data}, state) do
    case Client.auth(state.conn, reason_code, authentication_method, authentication_data) do
      {:ok, _, conn} ->
        {:noreply, %State{state | conn: conn}}

      {:error, _error} ->
        # TODO: Handle errors
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:publish, topic_name, payload, options}, state) do
    case Client.publish(state.conn, topic_name, payload, options) do
      {:ok, _, conn} ->
        {:noreply, %State{state | conn: conn}}

      {:error, _error} ->
        # TODO: Handle errors
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:subscribe, topic_filters}, state) do
    case Client.subscribe(state.conn, topic_filters) do
      {:ok, _, conn} ->
        {:noreply, %State{state | conn: conn}}

      {:error, _error} ->
        # TODO: Handle errors
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:connect_timeout, %State{conn: %Conn{state: :connecting}} = state) do
    # The server has not replied with CONNACK in time. Perhaps it is not a MQTT
    # server, the server application is too slow, or network quality is poor.
    #
    # We choose to defer to the user rather than retrying automatically. In some
    # cases, retrying with the same timeout will never succeed. The user should
    # terminate this worker instance and create another one.

    {:ok, conn} = Client.disconnect(state.conn)

    next_state =
      emit_event(
        %State{state | conn: conn},
        {:error, %MQTT.TransportError{reason: :connect_timeout}}
      )

    {:noreply, next_state}
  end

  @impl true
  def handle_info(:connect_timeout, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:keep_alive, %State{conn: %Conn{state: :connected}} = state) do
    # If Keep Alive is non-zero and in the absence of sending any other MQTT
    # Control Packets, the Client MUST send a PINGREQ packet [MQTT-3.1.2-20].

    case Client.ping(state.conn) do
      {:ok, _, conn} ->
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
  def handle_info(:reconnect, %State{conn: %Conn{state: conn_state}} = state)
      when conn_state in [:disconnected] do
    conn =
      case Client.reconnect(state.conn) do
        {:ok, _, conn} ->
          {:ok, conn} = Client.set_mode(conn, :active)

          conn

        {:error, %TransportError{}, conn} ->
          conn
      end

    {:noreply, %State{state | conn: conn}}
  end

  def handle_info(:reconnect, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(message, state) do
    case Client.data_received(state.conn, message) do
      {:ok, conn, :closed} ->
        next_state = emit_event(state, {:disconnected, :transport_closed})

        {:noreply, %State{next_state | conn: conn}}

      {:ok, conn, packets} ->
        Logger.debug(
          "pid=#{inspect(self())}, event=received_packets, packets=#{inspect(packets)}"
        )

        {:ok, conn} = Client.set_mode(conn, :active)

        next_state = handle_packets(%State{state | conn: conn}, packets)

        {:noreply, next_state}

      {:error, %Error{} = error} ->
        {:noreply, handle_error(state, error)}

      {:error, %TransportError{} = error} ->
        {:noreply, handle_error(state, error)}
    end
  end

  # HELPERS

  defp try_to_connect(args) do
    endpoint = Keyword.get(args, :endpoint)

    with {:ok, _, conn} <- Client.connect(endpoint, args),
         {:ok, conn} <- Client.set_mode(conn, :active) do
      {handler_mod, handler_opts} = Keyword.get(args, :handler)
      {:ok, handler_state} = handler_mod.init(handler_opts)

      {:noreply,
       %State{conn: conn, options: args, handler: handler_mod, handler_state: handler_state}}
    else
      {:error, error, conn} ->
        Logger.error("Unable to connect to #{inspect(endpoint)}: #{Exception.message(error)}")
        reconnect_strategy = Keyword.get(args, :reconnect_strategy)

        if !is_nil(reconnect_strategy) do
          Logger.info(
            "Will retry to connect to #{inspect(endpoint)} using #{inspect(reconnect_strategy)}"
          )

          {:noreply, conn}
        else
          {:stop, :normal, args}
        end
    end
  end

  defp handle_error(state, %MQTT.Error{} = error) do
    {:ok, conn} = Client.disconnect(state.conn, error.reason_code, Error.reason_string(error))

    emit_event(%State{state | conn: conn}, {:error, error})
  end

  defp handle_error(state, %MQTT.TransportError{} = error) do
    emit_event(state, {:disconnected, error})
  end

  defp handle_packets(state, packets) do
    Enum.reduce(packets, state, &handle_packet/2)
  end

  defp handle_packet(packet, state) do
    # TODO: Handle PUBACK, PUBREC, PUBCOMP
    event =
      case packet do
        %Packet.Auth{} ->
          {:auth, packet}

        %Packet.Connack{} ->
          if packet.reason_code == :server_moved || packet.reason_code == :use_another_server do
            {:redirected, packet}
          else
            {:connected, packet}
          end

        %Packet.Disconnect{} ->
          if packet.reason_code == :server_moved || packet.reason_code == :use_another_server do
            {:redirected, packet}
          else
            {:disconnected, packet}
          end

        %Packet.Publish{} ->
          {:publish, packet}

        %Packet.Pingresp{} ->
          {:pong, packet}

        %Packet.Suback{} ->
          {:subscription, packet}

        %Packet.Unsuback{} ->
          {:subscription, packet}
      end

    state
    |> process_event(event)
    |> emit_event(event)
  end

  defp process_event(state, {:redirected, packet}) do
    if !is_nil(packet.properties.server_reference) do
      {:ok, _conn} = Client.disconnect(state.conn)

      endpoint =
        choose_endpoint(packet.properties.server_reference)

      {handler_mod, handler_opts} = Keyword.get(state.options, :handler)
      {:ok, handler_state} = handler_mod.init(handler_opts)

      # TODO: Handle errors
      {:ok, _, conn} = Client.connect(endpoint, state.options)
      {:ok, conn} = Client.set_mode(conn, :active)

      %State{conn: conn, handler: handler_mod, handler_state: handler_state}
    else
      {:ok, conn} = Client.disconnect(state.conn)

      %State{state | conn: conn}
    end
  end

  defp process_event(state, {:disconnected, _packet}) do
    {:ok, conn} = Client.disconnect(state.conn)

    %State{state | conn: conn}
  end

  defp process_event(state, _), do: state

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

  defp choose_endpoint(server_reference) when is_binary(server_reference) do
    if String.starts_with?(server_reference, "[") do
      case String.split(String.trim_leading(server_reference, "["), "]:") do
        [host, port] -> {host, String.to_integer(port)}
        [host] -> host
      end
    else
      case String.split(server_reference, ":") do
        [host, port] -> {host, String.to_integer(port)}
        [host] -> host
      end
    end
  end
end
