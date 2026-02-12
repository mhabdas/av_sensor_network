defmodule ElixirconfAvNetwork.Hardware.ArduinoSupervisor do
  @moduledoc """
  Supervisor for the Arduino hardware.

  For the host, it uses a simulated Arduino connection.
  For the target, it uses a real Arduino connection.
  """
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    port = Application.get_env(:elixirconf_av_network, :arduino_port, "ttyACM0")

    children = [
      {ElixirconfAvNetwork.Hardware.ArduinoConnection,
       [port: port, baud: 115_200, name: :arduino_data_source]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
