defmodule MQTT.Transport.Websocket do
  require Logger

  alias MQTT.TransportError

  @subprotocol_header {"sec-websocket-protocol", "mqtt"}

  defstruct [:conn, :websocket, :ref]

  def close(%__MODULE__{} = handle) do
    {:ok, _conn} = Mint.HTTP.close(handle.conn)

    :ok
  end

  def connect(host, opts) when is_binary(host) do
    connect({host, default_port(opts)}, opts)
  end

  def connect({host, port}, opts) when is_binary(host) and is_integer(port) do
    has_required_dependencies?() ||
      raise """
        mint_web_socket is required to use the Websocket transport
      """

    {http_scheme, ws_scheme} =
      if Keyword.get(opts, :tls, false) do
        {:https, :wss}
      else
        {:http, :ws}
      end

    websocket_path = Keyword.get(opts, :path, "/")

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, host, port),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(ws_scheme, conn, websocket_path, [@subprotocol_header]),
         http_reply_message <- receive(do: (message -> message)),
         {:ok, conn, [{:status, ^ref, status}, {:headers, ^ref, resp_headers}, {:done, ^ref}]} <-
           Mint.WebSocket.stream(conn, http_reply_message),
         {:ok, conn, websocket} <-
           Mint.WebSocket.new(conn, ref, status, resp_headers),
         {:ok, conn} <- Mint.HTTP.set_mode(conn, :passive) do
      {:ok, %__MODULE__{conn: conn, websocket: websocket, ref: ref}}
    else
      error -> wrap_error(error)
    end
  end

  def data_received(handle, {type, socket, data}) when type in [:tcp, :ssl] do
    case Mint.HTTP.get_socket(handle.conn) do
      ^socket ->
        with {:ok, websocket, [{:binary, payload}]} <-
               Mint.WebSocket.decode(handle.websocket, data) do
          {:ok, %__MODULE__{handle | websocket: websocket}, payload}
        else
          error -> wrap_error(error)
        end

      _ ->
        :unknown
    end
  end

  def data_received(handle, {type, socket}) when type in [:tcp_closed, :ssl_closed] do
    case Mint.HTTP.get_socket(handle.conn) do
      ^socket ->
        {:ok, :closed}

      _ ->
        :unknown
    end
  end

  def data_received(_, _), do: :unknown

  def recv(%__MODULE__{} = handle, byte_count, timeout) do
    %__MODULE__{ref: ref} = handle

    with {:ok, conn, [{:data, ^ref, data}]} <-
           Mint.WebSocket.recv(handle.conn, byte_count, timeout),
         {:ok, websocket, [{:binary, payload}]} <- Mint.WebSocket.decode(handle.websocket, data) do
      {:ok, %__MODULE__{handle | conn: conn, websocket: websocket}, payload}
    else
      error -> wrap_error(error)
    end
  end

  def send(%__MODULE__{} = handle, payload) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(handle.websocket, {:binary, payload}),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(handle.conn, handle.ref, data) do
      {:ok, %__MODULE__{handle | conn: conn, websocket: websocket}}
    else
      error -> wrap_error(error)
    end
  end

  def set_mode(handle, mode) do
    {:ok, conn} = Mint.HTTP.set_mode(handle.conn, mode)

    {:ok, %__MODULE__{handle | conn: conn}}
  end

  defp wrap_error({:error, _websocket, reason, _}), do: {:error, %TransportError{reason: reason}}
  defp wrap_error({:error, _websocket, reason}), do: {:error, %TransportError{reason: reason}}
  defp wrap_error({:error, reason}), do: {:error, %TransportError{reason: reason}}
  defp wrap_error(other), do: other

  defp has_required_dependencies? do
    Code.ensure_loaded?(Mint.HTTP) && Code.ensure_loaded?(Mint.WebSocket)
  end

  defp default_port(opts) do
    if Keyword.get(opts, :tls, false) do
      443
    else
      80
    end
  end
end
