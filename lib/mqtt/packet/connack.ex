defmodule MQTT.Packet.Connack do
  import MQTT.PacketDecoder, only: [decode_properties: 1, decode_reason_code: 2]
  alias MQTT.PacketEncoder

  @control_packet_type 2
  @fixed_header_flags 0

  defstruct [:flags, :reason_code, :properties]

  def decode(data) do
    with {:ok, flags, rest} <- __MODULE__.Flags.decode(data),
         {:ok, reason_code, rest} <- decode_reason_code(:connack, rest),
         {:ok, properties, _, rest} <- decode_properties(rest),
         {:ok, properties} <- __MODULE__.Properties.from_decoder(properties) do
      {:ok,
       %__MODULE__{
         flags: flags,
         reason_code: reason_code,
         properties: properties
       }, rest}
    end
  end

  def encode!(%__MODULE__{} = packet) do
    connect_acknowledge_flags = __MODULE__.Flags.encode!(packet.flags)
    reason_code = PacketEncoder.encode_reason_code(packet.reason_code)
    properties = __MODULE__.Properties.encode!(packet.properties)

    variable_header =
      connect_acknowledge_flags <> reason_code <> properties

    remaining_length = byte_size(variable_header)

    fixed_header =
      <<@control_packet_type::4, @fixed_header_flags::4>> <>
        PacketEncoder.encode_variable_byte_integer(remaining_length)

    fixed_header <> variable_header
  end
end

defmodule MQTT.Packet.Connack.Flags do
  defstruct session_present?: false

  def decode(<<0::7, session_present_flag::1>> <> rest) do
    {:ok, %__MODULE__{session_present?: session_present_flag == 1}, rest}
  end

  def decode(data) when bit_size(data) < 8 do
    {:error, :incomplete_packet, data}
  end

  def encode!(%__MODULE__{} = flags) do
    session_present_flag =
      if flags.session_present? do
        1
      else
        0
      end

    <<0::7, session_present_flag::1>>
  end
end

defmodule MQTT.Packet.Connack.Properties do
  use MQTT.PacketProperties, properties: ~w(
    session_expiry_interval receive_maximum maximum_qos
    retain_available maximum_packet_size assigned_client_identifier
    topic_alias_maximum reason_string user_property
    wildcard_subscription_available subscription_identifiers_available
    shared_subscription_available server_keep_alive response_information
    server_reference authentication_method authentication_data
  )a

  @type t :: %__MODULE__{
          session_expiry_interval: non_neg_integer() | nil,
          receive_maximum: non_neg_integer() | nil,
          maximum_qos: non_neg_integer() | nil,
          retain_available: non_neg_integer() | nil,
          maximum_packet_size: non_neg_integer() | nil,
          assigned_client_identifier: String.t() | nil,
          topic_alias_maximum: non_neg_integer() | nil,
          reason_string: String.t() | nil,
          user_property: [{String.t(), String.t()}] | nil,
          wildcard_subscription_available: non_neg_integer() | nil,
          subscription_identifiers_available: non_neg_integer() | nil,
          shared_subscription_available: non_neg_integer() | nil,
          server_keep_alive: non_neg_integer() | nil,
          response_information: String.t() | nil,
          server_reference: String.t() | nil,
          authentication_method: String.t() | nil,
          authentication_data: binary() | nil
        }
end
