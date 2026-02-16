import Config

# Add configuration that is only needed when running on the host here.

# Arduino ports: omit to use autodetect (identifies by sensor data: POT/BTN → interactive).
# Or use arduino_*_serial for stable assignment when you swap USB cables (run mix arduino.ports).
config :elixirconf_av_network,
  arduino_port: "/dev/cu.usbmodem101"

# arduino_interactive_port: "/dev/cu.usbmodem101"
# arduino_interactive_serial: "YOUR_SERIAL"   # from mix arduino.ports

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
