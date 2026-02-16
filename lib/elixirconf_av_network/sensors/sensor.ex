defmodule ElixirconfAvNetwork.Sensors.Sensor do
  @moduledoc """
  Process per sensor - each sensor has its own isolated process.
  Handles its own data and routes to outputs (e.g. AudioEngine).
  """
  alias ElixirconfAvNetwork.Output.AudioEngine

  use GenServer

  require Logger

  @default_poll_interval_ms 1000

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    opts = Keyword.delete(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Read the current value of the sensor by pid or sensor_key.
  """
  def read(pid) when is_pid(pid) do
    GenServer.call(pid, :read)
  end

  def read(sensor_key) when is_binary(sensor_key) or is_atom(sensor_key) do
    case ElixirconfAvNetwork.Sensors.SensorRegistry.whereis(to_string(sensor_key)) do
      :undefined -> {:error, :not_found}
      pid -> read(pid)
    end
  end

  def init(opts) do
    sensor_key = Keyword.fetch!(opts, :sensor_key)
    data_source = Keyword.fetch!(opts, :data_source)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)

    state = %{
      sensor_key: sensor_key,
      data_source: data_source,
      poll_interval_ms: poll_interval_ms,
      value: nil,
      timestamp: nil
    }

    Process.send_after(self(), :poll, 100)

    {:ok, state}
  end

  def handle_call(:read, _from, state) do
    {:reply, {:ok, state.value, state.timestamp}, state}
  end

  def handle_info(:poll, state) do
    value = fetch_sensor_value(state.data_source, state.sensor_key)
    timestamp = if value != nil, do: System.system_time(:millisecond), else: state.timestamp

    with {:ok, new_value} <- validate(value),
         true <- new_value != state.value do
      AudioEngine.handle(state.sensor_key, new_value)
    end

    new_state = %{state | value: value, timestamp: timestamp}
    Process.send_after(self(), :poll, state.poll_interval_ms)
    {:noreply, new_state}
  end

  defp fetch_sensor_value(data_source, sensor_key) do
    case GenServer.call(data_source, :get_readings) do
      {:ok, readings} when is_map(readings) ->
        Map.get(readings, sensor_key) || Map.get(readings, to_string(sensor_key))

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp validate(nil), do: {:error, :no_value}
  defp validate(value) when is_integer(value), do: {:ok, value}
  defp validate(_), do: {:error, :invalid_value}
end
