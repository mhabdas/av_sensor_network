defmodule ElixirconfAvNetwork.Hardware.ArduinoConnection do
  @moduledoc """
  Connection to the Arduino via UART. Receives data and parses it for the Sensors.
  """
  alias ElixirconfAvNetwork.Hardware.ProtocolBinary
  alias ElixirconfAvNetwork.Hardware.ProtocolJson
  alias ElixirconfAvNetwork.Sensors.SensorSupervisor

  use GenServer

  require Logger

  @doc """
  Name of the process used by the Sensors for lookup. Constant for both implementations.
  """
  def data_source_name, do: :arduino_data_source

  def start_link(opts) do
    name = Keyword.get(opts, :name, data_source_name())
    opts = Keyword.delete(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Get the readings from the Arduino.
  """
  def get_readings(pid) do
    GenServer.call(pid, :get_readings)
  end

  @spec init(keyword()) ::
          {:ok,
           %{
             baud: any(),
             buffer: <<>>,
             port: any(),
             readings: map(),
             uart: any(),
             uart_module: atom()
           }}
          | {:stop, any()}
  def init(opts) when is_list(opts) do
    protocol = Application.get_env(:elixirconf_av_network, :protocol)

    framing =
      case protocol do
        :binary -> {Circuits.UART.Framing.None}
        :json -> {Circuits.UART.Framing.Line, separator: "\n"}
      end

    port = Keyword.get(opts, :port)
    baud = Keyword.get(opts, :baud, 115_200)
    uart_module = Keyword.get(opts, :uart_module, Circuits.UART)

    with {:ok, uart_pid} <- uart_module.start_link([]),
         :ok <- uart_module.open(uart_pid, port, speed: baud, active: true, framing: framing),
         :ok <- uart_module.flush(uart_pid, :both) do
      Logger.info("UART port opened successfully: #{port}")

      {:ok,
       %{
         uart: uart_pid,
         port: port,
         baud: baud,
         uart_module: uart_module,
         readings: %{},
         buffer: <<>>
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to open Arduino connection: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  def handle_call(:read, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_readings, _from, state) do
    {:reply, {:ok, Map.get(state, :readings, %{})}, state}
  end

  def handle_info({:circuits_uart, _port_id, data}, state) when is_binary(data) do
    protocol = Application.get_env(:elixirconf_av_network, :protocol)
    {readings, new_buffer} = process_data(protocol, data, state)

    Enum.each(readings, fn {sensor_key, _value} ->
      SensorSupervisor.start_sensor_if_needed(sensor_key)
    end)

    {:noreply, %{state | readings: readings, buffer: new_buffer}}
  end

  def handle_info({:circuits_uart, _port_id, {:error, reason}}, state) do
    Logger.warning("UART error: #{inspect(reason)}")
    {:noreply, state}
  end

  def terminate(_reason, state) do
    if Map.has_key?(state, :uart) do
      uart_module = Map.get(state, :uart_module, Circuits.UART)
      uart_module.close(state.uart)
    end
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
