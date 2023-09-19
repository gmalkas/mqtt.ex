defmodule MQTT.Packet.Connect.Flags do
  defstruct user_name?: false,
            password?: false,
            will_retain?: false,
            will_qos: 0,
            will_flag?: false,
            clean_start?: false
end

defmodule MQTT.Packet.Connect.Payload do
  defstruct [:client_id]
end

defmodule MQTT.Packet.Connect do
  alias MQTT.PacketEncoder

  @control_packet_type 1
  @fixed_header_flags 0

  defstruct [:protocol_name, :protocol_version, :flags, :keep_alive, :properties, :payload]

  def encode!(%__MODULE__{} = packet) do
    protocol_name = PacketEncoder.encode_utf8_string(packet.protocol_name)
    protocol_version = PacketEncoder.encode_variable_byte_integer(packet.protocol_version)

    user_name_flag = if packet.flags.user_name?, do: 1, else: 0
    password_flag = if packet.flags.password?, do: 1, else: 0
    will_retain = if packet.flags.will_retain?, do: 1, else: 0
    will_flag = if packet.flags.will_flag?, do: 1, else: 0
    clean_start = if packet.flags.clean_start?, do: 1, else: 0

    connect_flags =
      <<user_name_flag::1, password_flag::1, will_retain::1, packet.flags.will_qos::2,
        will_flag::1, clean_start::1, 0::1>>

    keep_alive = PacketEncoder.encode_two_byte_integer(packet.keep_alive)
    properties = PacketEncoder.encode_properties(packet.properties)

    variable_header =
      protocol_name <> protocol_version <> connect_flags <> keep_alive <> properties

    client_id = PacketEncoder.encode_utf8_string(packet.payload.client_id)

    payload = client_id

    remaining_length = byte_size(variable_header) + byte_size(payload)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header <> payload
  end
end
