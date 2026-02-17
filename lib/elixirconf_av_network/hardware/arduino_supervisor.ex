defmodule ElixirconfAvNetwork.Hardware.ArduinoSupervisor do
  @moduledoc """
  Supervisor for the Arduino hardware.

  When ports are not configured, starts connections with `port: :auto`—detection
  runs asynchronously after boot so startup is not blocked.
  """
  use Supervisor

  alias ElixirconfAvNetwork.Hardware.ArduinoConnection

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    inter_port = Application.get_env(:elixirconf_av_network, :arduino_interactive_port)
    env_port = Application.get_env(:elixirconf_av_network, :arduino_environmental_port)

    # Explicit ports → connect immediately. Otherwise → :auto, detect async
    inter_opts = [
      port: inter_port || :auto,
      role: :interactive,
      baud: 115_200,
      name: ArduinoConnection.interactive_name()
    ]

    env_opts = [
      port: env_port || :auto,
      role: :environmental,
      baud: 115_200,
      name: ArduinoConnection.environmental_name()
    ]

    children = [
      # Autodetect: uncomment when using port: :auto
      # ElixirconfAvNetwork.Hardware.ArduinoPortDetectorService,
      Supervisor.child_spec({ArduinoConnection, inter_opts},
        id: ArduinoConnection.interactive_name()
      ),
      Supervisor.child_spec({ArduinoConnection, env_opts},
        id: ArduinoConnection.environmental_name()
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
