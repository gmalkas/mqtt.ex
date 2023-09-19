defmodule MQTT.Client do
  require Logger

  @default_port 1883

  defstruct [:socket]

  def connect(ip_address, client_id, options \\ []) do
    port = Keyword.get(options, :port, @default_port)

    packet = MQTT.PacketBuilder.Connect.new(client_id)
    encoded_packet = MQTT.Packet.Connect.encode!(packet)

    Logger.info("ip_address=#{ip_address}, port=#{port}, action=connect")

    case tcp_connect(ip_address, port) do
      {:ok, socket} ->
        send_to_socket(socket, encoded_packet)

        {:ok, socket}
    end
  end

  # HELPERS
  defp tcp_connect(ip_address, port) do
    {:ok, ip_address} =
      ip_address
      |> String.to_charlist()
      |> :inet.parse_address()

    :gen_tcp.connect(ip_address, port, [
      :binary,
      packet: :line,
      active: false,
      keepalive: true,
      nodelay: true
    ])
  end

  defp send_to_socket(socket, packet) do
    Logger.debug("socket=#{inspect(socket)}, action=send, data=#{Base.encode16(packet)}")
    :ok = :gen_tcp.send(socket, packet)
  end
end
