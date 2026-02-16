defmodule ElixirconfAvNetwork.Hardware.ArduinoPortDetector do
  @moduledoc """
  Autodetects Arduino serial ports for interactive vs environmental use.

  Strategies (in order):
  1. **Serial number** - If `arduino_interactive_serial` / `arduino_environmental_serial` are
     set in config, matches ports by their USB serial number from `Circuits.UART.enumerate/0`.
  2. **Content-based probing** - When two Arduino-like ports are found and serial isn't
     configured, briefly opens each port and inspects the first sensor data. POT/BTN sensors
     → interactive; other sensor names → environmental.
  3. **Single port** - If only one Arduino-like port is found, uses it for interactive.

  Run `mix arduino.ports` to list available ports with their serial numbers for config.
  """

  require Logger

  alias ElixirconfAvNetwork.Hardware.ProtocolBinary
  alias ElixirconfAvNetwork.Hardware.ProtocolJson

  @interactive_prefixes ["POT", "BTN"]
  @probe_timeout_ms 3_000

  @app :elixirconf_av_network

  @doc """
  Detects which port to use for interactive and optionally environmental Arduinos.

  Returns `{:ok, %{interactive: port, environmental: port | nil}}` or `{:error, reason}`.
  """
  @spec detect() ::
          {:ok, %{interactive: String.t(), environmental: String.t() | nil}}
          | {:error, atom() | String.t()}
  def detect do
    with nil <- from_explicit_ports(),
         nil <- from_serial_numbers(),
         result <- from_content() do
      result
    end
  end

  defp from_explicit_ports do
    inter = Application.get_env(@app, :arduino_interactive_port)
    env = Application.get_env(@app, :arduino_environmental_port)
    if inter, do: {:ok, %{interactive: inter, environmental: env}}, else: nil
  end

  defp from_serial_numbers do
    inter = Application.get_env(@app, :arduino_interactive_serial)
    env = Application.get_env(@app, :arduino_environmental_serial)
    if inter || env, do: match_by_serial(inter, env), else: nil
  end

  defp match_by_serial(inter_serial, env_serial) do
    ports = Circuits.UART.enumerate()
    inter = inter_serial && find_by_serial(ports, inter_serial)
    env = env_serial && find_by_serial(ports, env_serial)

    cond do
      inter_serial && !inter ->
        {:error, "Serial #{inspect(inter_serial)} not found (interactive)"}

      env_serial && !env ->
        {:error, "Serial #{inspect(env_serial)} not found (environmental)"}

      inter ->
        {:ok, %{interactive: inter, environmental: env}}

      true ->
        from_content()
    end
  end

  defp find_by_serial(ports, target) do
    target = to_string(target)

    Enum.find_value(ports, fn {path, meta} ->
      case Map.get(meta, :serial_number) do
        nil ->
          nil

        serial ->
          (to_string(serial) == target or String.contains?(to_string(serial), target)) && path
      end
    end)
  end

  defp from_content do
    ports = arduino_ports()

    case ports do
      [] ->
        {:error, :no_ports_found}

      [one] ->
        Logger.info("ArduinoPortDetector: single port #{one} → interactive")
        {:ok, %{interactive: one, environmental: nil}}

      [a, b | _] ->
        probe_pair(a, b)
    end
  end

  defp probe_pair(port_a, port_b) do
    protocol = Application.get_env(@app, :protocol, :json)
    {inter, env} = assign_roles(port_a, probe(port_a, protocol), port_b, probe(port_b, protocol))
    if env, do: Logger.info("ArduinoPortDetector: #{inter} → interactive, #{env} → environmental")
    {:ok, %{interactive: inter, environmental: env}}
  end

  defp assign_roles(port_a, {:ok, :interactive}, port_b, {:ok, :environmental}),
    do: {port_a, port_b}

  defp assign_roles(port_a, {:ok, :environmental}, port_b, {:ok, :interactive}),
    do: {port_b, port_a}

  defp assign_roles(port_a, {:ok, :interactive}, _port_b, _), do: {port_a, nil}
  defp assign_roles(_port_a, _, port_b, {:ok, :interactive}), do: {port_b, nil}
  defp assign_roles(port_a, {:ok, :environmental}, port_b, _), do: {port_b, port_a}
  defp assign_roles(port_a, _, port_b, {:ok, :environmental}), do: {port_a, port_b}

  defp assign_roles(port_a, _, port_b, _) do
    Logger.warning(
      "ArduinoPortDetector: couldn't identify types, using #{port_a} for interactive. Run `mix arduino.ports` for serial numbers."
    )

    {port_a, port_b}
  end

  defp probe(port, protocol) do
    framing =
      if protocol == :binary,
        do: {Circuits.UART.Framing.None},
        else: {Circuits.UART.Framing.Line, separator: "\n"}

    with {:ok, pid} <- Circuits.UART.start_link([]),
         :ok <- Circuits.UART.open(pid, port, speed: 115_200, active: true, framing: framing) do
      result = await_first_sensor(pid, protocol)
      Circuits.UART.close(pid)
      result
    else
      err -> err
    end
  end

  defp await_first_sensor(uart_pid, protocol) do
    collect_until_classified(uart_pid, protocol, "")
  end

  defp collect_until_classified(uart_pid, protocol, buffer) do
    receive do
      {:circuits_uart, _id, data} when is_binary(data) ->
        case parse_sensor(protocol, buffer <> data) do
          {:classified, type} -> {:ok, type}
          {:incomplete, new_buf} -> collect_until_classified(uart_pid, protocol, new_buf)
        end
    after
      @probe_timeout_ms -> {:error, :no_data}
    end
  end

  defp parse_sensor(:json, buffer) do
    case String.split(buffer, "\n", parts: 2) do
      [line, rest] ->
        case ProtocolJson.parse_sensor_data(line) do
          {:ok, {name, _}} -> {:classified, sensor_type(name)}
          _ -> {:incomplete, rest}
        end

      [_] ->
        {:incomplete, buffer}
    end
  end

  defp parse_sensor(:binary, buffer) do
    case ProtocolBinary.extract_frame_from_buffer(buffer) do
      {:ok, {:ok, name, _}, _rest} -> {:classified, sensor_type(name)}
      :incomplete -> {:incomplete, buffer}
      {:error, _, rest} -> {:incomplete, rest}
    end
  end

  defp sensor_type(name) when is_binary(name) do
    if Enum.any?(@interactive_prefixes, &String.starts_with?(name, &1)),
      do: :interactive,
      else: :environmental
  end

  @doc "Returns Arduino-like serial ports with metadata. See `mix arduino.ports`."
  @spec list_ports() :: [{String.t(), map()}]
  def list_ports do
    Circuits.UART.enumerate()
    |> Enum.filter(&arduino_like?/1)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp arduino_ports, do: list_ports() |> Enum.map(&elem(&1, 0))

  defp arduino_like?({path, _}) do
    path =~ ~r/(usbmodem|ttyACM|ttyUSB)/i and
      not String.contains?(path, "Bluetooth") and
      not String.contains?(path, "debug")
  end
end
