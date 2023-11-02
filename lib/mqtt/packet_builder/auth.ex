defmodule MQTT.PacketBuilder.Auth do
  alias MQTT.Packet.Auth

  def new(reason_code, authentication_method, authentication_data \\ nil) do
    %Auth{
      reason_code: reason_code,
      properties: %Auth.Properties{
        authentication_method: authentication_method,
        authentication_data: authentication_data
      }
    }
  end
end
