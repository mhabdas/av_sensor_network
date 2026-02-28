import Config

# Add configuration that is only needed when running on the host here.

# Hardcoded ports – run `mix arduino.ports` to find yours (numbers vary per USB port)
config :elixirconf_av_network,
  arduino_interactive_port: "/dev/cu.usbmodem1101",
  arduino_environmental_port: "/dev/cu.usbmodem11201"

# Autodetect: comment ports above and uncomment below, then uncomment ArduinoPortDetectorService in arduino_supervisor.ex
# config :elixirconf_av_network,
#   arduino_port: "/dev/cu.usbmodem101"
# Or use arduino_*_serial (run mix arduino.ports for serial numbers)

config :nerves_runtime,
  kv_backend:
    {Nerves.Runtime.KVBackend.InMemory,
     contents: %{
       # The KV store on Nerves systems is typically read from UBoot-env, but
       # this allows us to use a pre-populated InMemory store when running on
       # host for development and testing.
       #
       # https://hexdocs.pm/nerves_runtime/readme.html#using-nerves_runtime-in-tests
       # https://hexdocs.pm/nerves_runtime/readme.html#nerves-system-and-firmware-metadata

       "nerves_fw_active" => "a",
       "a.nerves_fw_architecture" => "generic",
       "a.nerves_fw_description" => "N/A",
       "a.nerves_fw_platform" => "host",
       "a.nerves_fw_version" => "0.0.0"
     }}
