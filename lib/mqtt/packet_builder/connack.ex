defmodule MQTT.PacketBuilder.Connack do
  alias MQTT.Packet.Connack

  def new(reason_code \\ :success) do
    %Connack{
      properties: %Connack.Properties{},
      reason_code: reason_code,
      flags: %Connack.Flags{}
    }
  end

  def with_enhanced_authentication(
        %Connack{properties: %Connack.Properties{} = props} = packet,
        authentication_method,
        authentication_data \\ nil
      ) do
    %Connack{
      packet
      | properties: %Connack.Properties{
          props
          | authentication_method: authentication_method,
            authentication_data: authentication_data
        }
    }
  end

  def with_maximum_packet_size(
        %Connack{properties: %Connack.Properties{} = props} = packet,
        maximum_packet_size
      )
      when is_integer(maximum_packet_size) do
    %Connack{
      packet
      | properties: %Connack.Properties{
          props
          | maximum_packet_size: maximum_packet_size
        }
    }
  end

  def with_server_redirection(
        %Connack{properties: %Connack.Properties{} = props} = packet,
        reason_code,
        server_reference \\ nil
      )
      when reason_code in [:server_moved, :use_another_server] do
    %Connack{
      packet
      | properties: %Connack.Properties{props | server_reference: server_reference},
        reason_code: reason_code
    }
  end
end
