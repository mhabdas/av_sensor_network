defmodule ElixirconfAvNetwork.Output.OSCOutput do
  require Logger

  @osc_ip {127, 0, 0, 1}
  @osc_port 12000

  def send_message(address, arguments) do
    message = %OSCx.Message{
      address: address,
      arguments: arguments
    }

    encoded = OSCx.encode(message)

    case :gen_udp.open(0) do
      {:ok, socket} ->
        :gen_udp.send(socket, @osc_ip, @osc_port, encoded)
        :gen_udp.close(socket)
        :ok

      {:error, reason} ->
        Logger.error("OSC send failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
