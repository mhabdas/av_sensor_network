defmodule ElixirconfAvNetwork.Hardware.ArduinoConnection do
  @moduledoc """
  Connection to the Arduino via UART. Receives data and parses it for the Sensors.

  When `port: :auto`, detection runs asynchronously after start—boot is not blocked.
  """
  alias ElixirconfAvNetwork.Hardware.ArduinoPortDetectorService
  alias ElixirconfAvNetwork.Hardware.ProtocolBinary
  alias ElixirconfAvNetwork.Hardware.ProtocolJson
  alias ElixirconfAvNetwork.Sensors.SensorSupervisor

  use GenServer

  require Logger

  @retry_delay_ms 5_000

  # ——— Public API ———

  @doc "Name of the process for the interactive Arduino (buttons, potentiometers)."
  def interactive_name, do: :arduino_interactive
  @doc "Name of the process for the environmental Arduino (temperature, humidity, etc.)."
  def environmental_name, do: :arduino_environmental

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Get the readings from the Arduino."
  def get_readings(pid) do
    GenServer.call(pid, :get_readings)
  end

  # ——— GenServer callbacks ———

  def init(opts) when is_list(opts) do
    base = base_state(opts)
    port = Keyword.get(opts, :port)
    init_connection(port, base)
  end

  def handle_call(:get_readings, _from, state) do
    {:reply, {:ok, Map.get(state, :readings, %{})}, state}
  end

  def handle_info(:detect_port, %{connected: false} = state) do
    available_ports = Circuits.UART.enumerate()

    with port = find_port_for_role(available_ports, state.role),
         {:ok, uart_pid} <- open_uart(port, state.baud, state.uart_module) do
      Logger.info("UART port opened: #{port}")
      {:noreply, %{state | port: port, uart: uart_pid, connected: true}}
    else
      {:ok, nil} -> schedule_detect_retry(state)
      {:error, _} -> schedule_detect_retry(state)
    end
  end

  def handle_info(:detect_port, state), do: {:noreply, state}

  def handle_info(:retry_connect, %{connected: false} = state) do
    case open_uart(state.port, state.baud, state.uart_module) do
      {:ok, uart_pid} ->
        Logger.info("Connected to #{state.port}")
        {:noreply, %{state | uart: uart_pid, connected: true}}

      {:error, _} ->
        Process.send_after(self(), :retry_connect, @retry_delay_ms)
        {:noreply, state}
    end
  end

  def handle_info({:circuits_uart, _port_id, data}, state) when is_binary(data) do
    if state.uart, do: process_uart_data(data, state), else: {:noreply, state}
  end

  def handle_info({:circuits_uart, _port_id, {:error, reason}}, state)
      when reason in [:eio, :einval, :enotconn, :epipe] do
    Logger.warning("Arduino #{state.role} disconnected - clearing readings")
    {:noreply, %{state | connected: false, readings: %{}}}
  end

  def handle_info({:circuits_uart, _port_id, {:error, reason}}, state) do
    Logger.warning("UART error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info(:check_connection, %{connected: false, port: port} = state)
      when is_binary(port) do
    case open_uart(port, state.baud, state.uart_module) do
      {:ok, uart_pid} ->
        Logger.info("Arduino #{state.role} reconnected to #{port}!")
        Process.send_after(self(), :check_connection, 5_000)
        {:noreply, %{state | uart: uart_pid, connected: true}}

      {:error, _} ->
        Process.send_after(self(), :check_connection, 5_000)
        {:noreply, state}
    end
  end

  def handle_info(:check_connection, state) do
    Process.send_after(self(), :check_connection, 5_000)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  def terminate(_reason, state) do
    if state[:uart] do
      (state[:uart_module] || Circuits.UART).close(state.uart)
    end
  end

  # ——— Private: init & connection ———

  defp init_connection(port, base) when port == :auto or is_nil(port) do
    send(self(), :detect_port)
    {:ok, Map.merge(base, %{port: nil, uart: nil, connected: false})}
  end

  defp init_connection(port, base) when is_binary(port) do
    Process.send_after(self(), :check_connection, 5_000)

    case open_uart(port, base.baud, base.uart_module) do
      {:ok, uart_pid} ->
        {:ok, Map.merge(base, %{port: port, uart: uart_pid, connected: true})}

      {:error, reason} ->
        Logger.warning("Port #{port} not available: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :retry_connect, @retry_delay_ms)
        {:ok, Map.merge(base, %{port: port, uart: nil, connected: false})}
    end
  end

  defp base_state(opts) do
    %{
      name: Keyword.get(opts, :name),
      role: Keyword.get(opts, :role),
      baud: Keyword.get(opts, :baud, 115_200),
      uart_module: Keyword.get(opts, :uart_module, Circuits.UART),
      readings: %{},
      buffer: <<>>
    }
  end

  defp schedule_detect_retry(state) do
    Process.send_after(self(), :detect_port, @retry_delay_ms)
    {:noreply, state}
  end

  # ——— Private: UART & data processing ———

  defp find_port_for_role(available_ports, role) do
    arduino_ports =
      available_ports
      |> Enum.filter(fn {path, _} -> path =~ ~r/(usbmodem|ttyACM|ttyUSB)/i end)
      |> Enum.sort_by(fn {path, _} -> path end)

    case {role, arduino_ports} do
      {:interactive, [{port, _} | _]} -> port
      {:environmental, [_, {port, _} | _]} -> port
      _ -> nil
    end
  end

  defp open_uart(port, baud, uart_module) do
    protocol = Application.get_env(:elixirconf_av_network, :protocol)

    framing =
      if protocol == :binary,
        do: {Circuits.UART.Framing.None},
        else: {Circuits.UART.Framing.Line, separator: "\n"}

    with {:ok, pid} <- uart_module.start_link([]),
         :ok <- uart_module.open(pid, port, speed: baud, active: true, framing: framing),
         :ok <- uart_module.flush(pid, :both) do
      {:ok, pid}
    else
      {:error, :enoent} -> {:error, :enoent}
      other -> other
    end
  end

  defp process_uart_data(data, state) do
    protocol = Application.get_env(:elixirconf_av_network, :protocol)
    {readings, new_buffer} = process_data(protocol, data, state)

    Enum.each(readings, fn {sensor_key, _value} ->
      SensorSupervisor.start_sensor_if_needed(sensor_key, state.name)
    end)

    {:noreply, %{state | readings: readings, buffer: new_buffer}}
  end

  defp process_data(:json, data, state) do
    case ProtocolJson.parse_sensor_data(data) do
      {:ok, {sensor_name, value}} ->
        {Map.put(state.readings, sensor_name, value), <<>>}

      {:error, _} ->
        {state.readings, <<>>}
    end
  end

  defp process_data(:binary, data, state) do
    buffer = state.buffer <> data
    extract_binary_frames(buffer, state.readings)
  end

  defp process_data(_, _data, state) do
    {state.readings, state.buffer}
  end

  defp extract_binary_frames(buffer, readings_acc) do
    case ProtocolBinary.extract_frame_from_buffer(buffer) do
      {:ok, {:ok, sensor_name, value}, rest} ->
        readings = Map.put(readings_acc, sensor_name, value)
        extract_binary_frames(rest, readings)

      {:error, :checksum_mismatch, rest} ->
        extract_binary_frames(rest, readings_acc)

      :incomplete ->
        {readings_acc, buffer}
    end
  end
end
