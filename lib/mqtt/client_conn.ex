defmodule MQTT.ClientConn do
  alias MQTT.Packet

  defstruct [:ip_address, :port, :client_id, :socket, :state, :read_buffer]

  def connecting(ip_address, port, client_id, socket) when is_port(socket) do
    %__MODULE__{
      client_id: client_id,
      ip_address: ip_address,
      port: port,
      read_buffer: "",
      socket: socket,
      state: :connecting
    }
  end

  def handle_packet_from_server(%__MODULE__{} = conn, %Packet.Connack{} = _packet, buffer) do
    %__MODULE__{conn | state: :connected, read_buffer: buffer}
  end
end
