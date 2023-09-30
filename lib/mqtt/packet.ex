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
    18 => {:assigned_client_identifier, :utf8_string},
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

  @reason_code_name_by_packet_type_and_value %{
    {:connack, 0} => :success,
    {:connack, 134} => :bad_user_name_or_password,
    {:puback, 0} => :success,
    {:disconnect, 0} => :normal_disconnection,
    {:suback, 0} => :granted_qos_0,
    {:unsuback, 0} => :success
  }
  @reason_code_by_name Enum.map(@reason_code_name_by_packet_type_and_value, fn {{_, value}, name} ->
                         {name, value}
                       end)
                       |> Map.new()

  def property_by_name!(name), do: Map.fetch!(@property_by_name, name)
  def property_names, do: @property_names

  def property_by_identifier(identifier) do
    Map.fetch(@property_by_identifier, identifier)
  end

  def packet_type_from_value(value), do: Map.fetch(@packet_type_by_value, value)

  def reason_code_name_by_packet_type_and_value(packet_type, value) do
    Map.fetch(@reason_code_name_by_packet_type_and_value, {packet_type, value})
  end

  def reason_code_by_name!(name) do
    Map.fetch!(@reason_code_by_name, name)
  end

  def wire_byte_size(:packet_identifier), do: 2
  def wire_byte_size({:utf8_string, value}) when is_binary(value), do: 2 + byte_size(value)
  def wire_byte_size({:variable_byte_integer, value}) when value <= 0x7F, do: 1
  def wire_byte_size({:variable_byte_integer, value}) when value <= 0xFF7F, do: 2
  def wire_byte_size({:variable_byte_integer, value}) when value <= 0xFFFF7F, do: 3
  def wire_byte_size({:variable_byte_integer, value}) when value <= 0xFFFFFF7F, do: 4
end
