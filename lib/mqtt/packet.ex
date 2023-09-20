defmodule MQTT.Packet do
  require Logger

  @packet_type_by_value %{
    0 => :reserved,
    1 => :connect,
    2 => :connack,
    3 => :publish,
    4 => :puback,
    5 => :pubrec,
    6 => :pubrel,
    7 => :pubcomp,
    8 => :subscribe,
    9 => :suback,
    10 => :unsubscribe,
    11 => :unsuback,
    12 => :pingreq,
    13 => :pingresp,
    14 => :disconnect,
    15 => :auth
  }

  @property_by_identifier %{
    1 => {:payload_format_indicator, :byte},
    2 => {:message_expiry_interval, :four_byte_integer},
    3 => {:content_type, :utf8_string},
    8 => {:response_topic, :binary},
    9 => {:correlation_data, :variable_byte_integer},
    17 => {:session_expiry_interval, :four_byte_integer},
    21 => {:authentication_method, :utf8_string},
    22 => {:authentication_data, :binary},
    23 => {:request_problem_information, :byte},
    24 => {:will_delay_interval, :four_byte_integer},
    25 => {:request_response_information, :byte},
    33 => {:receive_maximum, :two_byte_integer},
    34 => {:topic_alias_maximum, :two_byte_integer},
    38 => {:user_property, :utf8_string_pair},
    39 => {:maximum_packet_size, :four_byte_integer}
  }

  @property_by_name Enum.map(@property_by_identifier, fn {id, {name, type}} ->
                      {name, {id, type}}
                    end)
                    |> Map.new()
  @property_names Enum.map(@property_by_identifier, fn {_, {name, _}} -> name end)

  @reason_code_name_by_value %{
    0 => :success,
    128 => :unspecified_error,
    129 => :malformed_packet,
    130 => :protocol_error,
    131 => :implementation_specific_error,
    132 => :unsupported_protocol_error,
    133 => :client_identifier_not_valid,
    134 => :bad_user_name_or_password,
    135 => :not_authorized,
    136 => :server_unavailable,
    137 => :server_busy,
    138 => :banned,
    140 => :bad_authentication_method,
    144 => :topic_name_invalid,
    149 => :packet_too_large,
    151 => :quota_exceeded,
    153 => :payload_format_invalid,
    154 => :retain_not_supported,
    155 => :qos_not_supported,
    156 => :use_another_server,
    157 => :server_moved,
    159 => :connection_rate_exceeded
  }

  def property_by_name!(name), do: Map.fetch!(@property_by_name, name)
  def property_names, do: @property_names

  def property_by_identifier(identifier) do
    Map.fetch(@property_by_identifier, identifier)
  end

  def packet_type_from_value(value), do: Map.fetch(@packet_type_by_value, value)

  def reason_code_name_by_value(value) do
    Map.fetch(@reason_code_name_by_value, value)
  end
end
