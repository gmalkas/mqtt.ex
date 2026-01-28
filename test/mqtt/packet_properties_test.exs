defmodule MQTT.MockModule do
  use MQTT.PacketProperties, properties: ~w(retain_available reason_string user_property)a
end

defmodule MQTT.PacketPropertiesTest do
  use ExUnit.Case, async: true

  describe "from_decoder/1" do
    test "rejects unexpected properties" do
      assert {:error, error} = MQTT.MockModule.from_decoder(response_topic: "/topic")
      assert error.reason_code == :malformed_packet
    end

    test "uses default values for missing properties" do
      assert {:ok, properties} = MQTT.MockModule.from_decoder([])
      assert properties.retain_available == true
      assert properties.user_property == []
    end
  end
end
