defmodule MQTT.Packet do
  require Logger

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

  def property_by_name!(name), do: Map.fetch!(@property_by_name, name)
end
