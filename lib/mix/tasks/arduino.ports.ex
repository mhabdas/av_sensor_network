defmodule Mix.Tasks.Arduino.Ports do
  @shortdoc "List Arduino serial ports with serial numbers for config"
  @moduledoc """
  Lists available serial ports that look like Arduinos, with their USB serial numbers
  and other metadata.

  Use this to find serial numbers for `arduino_interactive_serial` and
  `arduino_environmental_serial` in config, so ports are identified correctly even
  when you swap USB cables or the order changes.

  ## Example

      $ mix arduino.ports

      Found 2 Arduino-like port(s):

        /dev/cu.usbmodem101
          serial_number: "ABC123"
          vendor_id: 2341
          product_id: 43
          description: "Arduino Uno"

        /dev/cu.usbmodem102
          serial_number: "XYZ789"
          vendor_id: 2341
          product_id: 43

      Add to config:
        config :elixirconf_av_network,
          arduino_interactive_serial: "ABC123",
          arduino_environmental_serial: "XYZ789"
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:circuits_uart)

    ports = ElixirconfAvNetwork.Hardware.ArduinoPortDetector.list_ports()

    if ports == [] do
      Mix.shell().info("No Arduino-like serial ports found.")
      Mix.shell().info("")
      Mix.shell().info("On host: connect an Arduino via USB and run again.")
      Mix.shell().info("On Linux: look for /dev/ttyACM* or /dev/ttyUSB*")
      Mix.shell().info("On macOS: look for /dev/cu.usbmodem*")
    else
      Mix.shell().info("Found #{length(ports)} Arduino-like port(s):")
      Mix.shell().info("")

      for {path, meta} <- ports do
        Mix.shell().info("  #{path}")

        for {key, value} <- meta do
          Mix.shell().info("    #{key}: #{inspect(value)}")
        end

        if Map.has_key?(meta, :serial_number) do
          serial = meta.serial_number
          Mix.shell().info("")
          Mix.shell().info("    → config: arduino_*_serial: #{inspect(serial)}")
        end

        Mix.shell().info("")
      end

      Mix.shell().info("Add serial numbers to config for stable port assignment.")
    end
  end
end
