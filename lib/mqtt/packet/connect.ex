defmodule MQTT.Packet.Connect do
  alias MQTT.PacketEncoder

  @control_packet_type 1
  @fixed_header_flags 0

  defstruct [:protocol_name, :protocol_version, :flags, :keep_alive, :properties, :payload]

  def encode!(%__MODULE__{} = packet) do
    protocol_name = PacketEncoder.encode_utf8_string(packet.protocol_name)
    protocol_version = PacketEncoder.encode_variable_byte_integer(packet.protocol_version)

    connect_flags = __MODULE__.Flags.encode!(packet.flags)
    keep_alive = PacketEncoder.encode_two_byte_integer(packet.keep_alive)
    properties = __MODULE__.Properties.encode!(packet.properties)

    variable_header =
      protocol_name <> protocol_version <> connect_flags <> keep_alive <> properties

    payload = __MODULE__.Payload.encode!(packet.payload)

    remaining_length = byte_size(variable_header) + byte_size(payload)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header <> payload
  end
end

defmodule MQTT.Packet.Connect.Properties do
  use MQTT.PacketProperties, properties: ~w(
    session_expiry_interval
    receive_maximum
    maximum_packet_size
    topic_alias_maximum
    request_response_information
    request_problem_information
    user_property
    authentication_method
    authentication_data
  )a
end

defmodule MQTT.Packet.Connect.Flags do
  defstruct user_name?: false,
            password?: false,
            will_retain?: false,
            will_qos: 0,
            will?: false,
            clean_start?: false

  def encode!(%__MODULE__{} = flags) do
    user_name_flag = if flags.user_name?, do: 1, else: 0
    password_flag = if flags.password?, do: 1, else: 0
    will_retain = if flags.will_retain?, do: 1, else: 0
    will_flag = if flags.will?, do: 1, else: 0
    clean_start = if flags.clean_start?, do: 1, else: 0

    <<user_name_flag::1, password_flag::1, will_retain::1, flags.will_qos::2, will_flag::1,
      clean_start::1, 0::1>>
  end
end

defmodule MQTT.Packet.Connect.Payload do
  alias MQTT.PacketEncoder

  defstruct [:client_id, :user_name, :password, :will_properties, :will_topic, :will_payload]

  def encode!(%__MODULE__{} = payload) do
    client_id = PacketEncoder.encode_utf8_string(payload.client_id)

    will_properties =
      if !is_nil(payload.will_properties) do
        __MODULE__.WillProperties.encode!(payload.will_properties)
      else
        <<>>
      end

    will_topic =
      if !is_nil(payload.will_topic) do
        PacketEncoder.encode_utf8_string(payload.will_topic)
      else
        <<>>
      end

    will_payload =
      if !is_nil(payload.will_payload) do
        PacketEncoder.encode_binary_data(payload.will_payload)
      else
        <<>>
      end

    user_name =
      if !is_nil(payload.user_name) do
        PacketEncoder.encode_utf8_string(payload.user_name)
      else
        <<>>
      end

    password =
      if !is_nil(payload.password) do
        PacketEncoder.encode_binary_data(payload.password)
      else
        <<>>
      end

    client_id <> will_properties <> will_topic <> will_payload <> user_name <> password
  end
end

defmodule MQTT.Packet.Connect.Payload.WillProperties do
  use MQTT.PacketProperties, properties: ~w(
    will_delay_interval
    payload_format_indicator
    message_expiry_interval
    content_type
    response_topic
    correlation_data
    user_property
  )a
end
