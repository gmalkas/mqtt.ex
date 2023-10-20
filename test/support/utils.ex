defmodule MQTT.Test.Utils do
  @client_id_byte_size 12
  @topic_byte_size 12

  def generate_client_id do
    @client_id_byte_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end

  def random_topic do
    @topic_byte_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode16()
  end

  def verify_cert(_cert, {:bad_cert, :selfsigned_peer}, state) do
    {:valid, state}
  end

  def verify_cert(_, {:extension, _}, state) do
    {:unknown, state}
  end
end
