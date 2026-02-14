defmodule ElixirconfAvNetwork.Hardware.ArduinoConnection do
  @moduledoc """
  Connection to the Arduino via UART. Receives data and parses it for the Sensors.
  """
  alias ElixirconfAvNetwork.Hardware.Protocol
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
    port = Keyword.get(opts, :port)
    baud = Keyword.get(opts, :baud, 115_200)
    uart_module = Keyword.get(opts, :uart_module, Circuits.UART)

    with {:ok, uart_pid} <- uart_module.start_link([]),
         :ok <- uart_module.open(uart_pid, port, speed: baud, active: true),
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
    buffer = state.buffer <> data
    {readings, new_buffer} = extract_all_frames(buffer, state.readings)

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

  defp extract_all_frames(buffer, readings_acc) do
    case Protocol.extract_frame_from_buffer(buffer) do
      {:ok, {:ok, sensor_name, value}, rest} ->
        readings = Map.put(readings_acc, sensor_name, value)
        extract_all_frames(rest, readings)

      {:error, :checksum_mismatch, rest} ->
        extract_all_frames(rest, readings_acc)

      :incomplete ->
        {readings_acc, buffer}
    end
  end
end
