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

  # https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901027
  @property_by_identifier %{
    1 => {:payload_format_indicator, :byte},
    2 => {:message_expiry_interval, :four_byte_integer},
    3 => {:content_type, :utf8_string},
    8 => {:response_topic, :binary},
    9 => {:correlation_data, :variable_byte_integer},
    11 => {:subscription_identifier, :variable_byte_integer},
    17 => {:session_expiry_interval, :four_byte_integer},
    18 => {:assigned_client_identifier, :utf8_string},
    19 => {:server_keep_alive, :two_byte_integer},
    21 => {:authentication_method, :utf8_string},
    22 => {:authentication_data, :binary},
    23 => {:request_problem_information, :byte},
    24 => {:will_delay_interval, :four_byte_integer},
    25 => {:request_response_information, :byte},
    26 => {:response_information, :utf8_string},
    28 => {:server_reference, :utf8_string},
    31 => {:reason_string, :utf8_string},
    33 => {:receive_maximum, :two_byte_integer},
    34 => {:topic_alias_maximum, :two_byte_integer},
    35 => {:topic_alias, :two_byte_integer},
    36 => {:maximum_qos, :byte},
    37 => {:retain_available, :byte},
    38 => {:user_property, :utf8_string_pair},
    39 => {:maximum_packet_size, :four_byte_integer},
    40 => {:wildcard_subscription_available, :byte},
    41 => {:subscription_identifiers_available, :byte},
    42 => {:shared_subscription_available, :byte}
  }

  @property_by_name Enum.map(@property_by_identifier, fn {id, {name, type}} ->
                      {name, {id, type}}
                    end)
                    |> Map.new()
  @property_names Enum.map(@property_by_identifier, fn {_, {name, _}} -> name end)

  # https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901031
  @reason_codes [
    {0, :success, ~w(connack puback pubrec pubrel pubcomp unsuback auth)a},
    {0, :normal_disconnection, ~w(disconnect)a},
    {0, :granted_qos_0, ~w(suback)a},
    {1, :granted_qos_1, ~w(suback)a},
    {2, :granted_qos_2, ~w(suback)a},
    {4, :disconnect_with_will_message, ~w(disconnect)a},
    {16, :no_matching_subscribers, ~w(puback pubrec)a},
    {17, :no_subscription_existed, ~w(unsuback)a},
    {24, :continue_authentication, ~w(auth)a},
    {25, :reauthenticate, ~w(auth)a},
    {128, :unspecified_error, ~w(connack puback pubrec suback unsuback disconnect)a},
    {129, :malformed_packet, ~w(connack disconnect)a},
    {130, :protocol_error, ~w(connack disconnect)a},
    {131, :implementation_specific_error, ~w(connack puback pubrec suback unsuback disconnect)a},
    {132, :unsupported_protocol_version, ~w(connack)a},
    {133, :client_identifier_not_valid, ~w(connack)a},
    {134, :bad_user_name_or_password, ~w(connack)a},
    {135, :not_authorized, ~w(connack puback pubrec suback unsuback disconnect)a},
    {136, :server_unavailable, ~w(connack)a},
    {137, :server_busy, ~w(connack disconnect)a},
    {138, :banned, ~w(connack)a},
    {139, :server_shutting_down, ~w(disconnect)a},
    {140, :bad_authentication_method, ~w(connack disconnect)a},
    {141, :keep_alive_timeout, ~w(disconnect)a},
    {142, :session_taken_over, ~w(disconnect)a},
    {143, :topic_filter_invalid, ~w(suback unsuback disconnect)a},
    {144, :topic_name_invalid, ~w(connack puback pubrec disconnect)a},
    {145, :packet_identifier_in_use, ~w(puback pubrec suback unsuback)a},
    {146, :packet_identifier_not_found, ~w(pubrel pubcomp)a},
    {147, :receive_maximum_exceeded, ~w(disconnect)a},
    {148, :topic_alias_invalid, ~w(disconnect)a},
    {149, :packet_too_large, ~w(connack disconnect)a},
    {150, :message_rate_too_high, ~w(disconnect)a},
    {151, :quota_exceeded, ~w(connack puback pubrec suback disconnect)a},
    {152, :administrative_action, ~w(disconnect)a},
    {153, :payload_format_invalid, ~w(connack puback pubrec disconnect)a},
    {154, :retain_not_supported, ~w(connack disconnect)a},
    {155, :qos_not_supported, ~w(connack disconnect)a},
    {156, :use_another_server, ~w(connack disconnect)a},
    {157, :server_moved, ~w(connack disconnect)a},
    {158, :shared_subscriptions_not_supported, ~w(suback disconnect)a},
    {159, :connection_rate_exceeded, ~w(connack disconnect)a},
    {160, :maximum_connect_time, ~w(disconnect)a},
    {161, :subscription_identifiers_not_supported, ~w(suback disconnect)a},
    {162, :wildcard_subscriptions_not_supported, ~w(suback disconnect)a}
  ]

  @reason_code_name_by_packet_type_and_value @reason_codes
                                             |> Enum.flat_map(fn {value, name, packet_types} ->
                                               Enum.map(packet_types, &{{&1, value}, name})
                                             end)
                                             |> Map.new()
  %{
    {:connack, 0} => :success,
    {:connack, 134} => :bad_user_name_or_password,
    {:puback, 0} => :success,
    {:pubrec, 0} => :success,
    {:pubrel, 0} => :success,
    {:pubcomp, 0} => :success,
    {:puback, 131} => :implementation_specific_error,
    {:disconnect, 0} => :normal_disconnection,
    {:disconnect, 4} => :disconnect_with_will_message,
    {:suback, 0} => :granted_qos_0,
    {:unsuback, 0} => :success
  }

  @reason_code_by_name Enum.map(@reason_code_name_by_packet_type_and_value, fn {{_, value}, name} ->
                         {name, value}
                       end)
                       |> Map.new()
  @reason_code_error_threshold 0x80

  def encode!(%packet_module{} = packet)
      when packet_module in [
             __MODULE__.Auth,
             __MODULE__.Connack,
             __MODULE__.Connect,
             __MODULE__.Pubcomp,
             __MODULE__.Publish,
             __MODULE__.Pubrec,
             __MODULE__.Pubrel,
             __MODULE__.Subscribe,
             __MODULE__.Unsubscribe,
             __MODULE__.Disconnect,
             __MODULE__.Pingreq,
             __MODULE__.Pingresp
           ] do
    packet_module.encode!(packet)
  end

  def indicates_error?(%{reason_code: reason_code}) do
    reason_code_by_name!(reason_code) >= @reason_code_error_threshold
  end

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
