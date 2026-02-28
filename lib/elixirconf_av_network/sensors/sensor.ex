defmodule ElixirconfAvNetwork.Sensors.Sensor do
  @moduledoc """
  Process per sensor - each sensor has its own isolated process.
  Handles its own data and routes to outputs (e.g. AudioEngine).
  """
  alias ElixirconfAvNetwork.Output.AudioEngine

  use GenServer

  require Logger

  @default_poll_interval_ms 1000
  @timeout_ms 5_000

  @spec start_link(keyword()) :: :ignore | {:error, any()} | {:ok, pid()}
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
      timestamp: nil,
      timed_out: false
    }

    Process.send_after(self(), :poll, 100)

    {:ok, state}
  end

  def handle_call(:read, _from, state) do
    {:reply, {:ok, state.value, state.timestamp}, state}
  end

  def handle_info(
        :poll,
        %{
          sensor_key: sensor_key,
          data_source: data_source,
          timestamp: timestamp,
          poll_interval_ms: poll_interval_ms,
          value: value,
          timed_out: timed_out
        } = state
      ) do
    sensor_value = fetch_sensor_value(data_source, sensor_key)
    now = System.system_time(:millisecond)
    is_timeout = timeout?(timestamp, now, sensor_key)

    if is_timeout and not timed_out do
      Logger.warning("TIMEOUT TRIGGERED for #{state.sensor_key}!")
      handle_timeout(sensor_key, value)
    end

    if sensor_value != nil and timed_out do
      Logger.warning("TIMEOUT CLEARED for #{state.sensor_key}!")
    end

    with {:ok, new_value} <- validate(sensor_value),
         true <- new_value != value do
      AudioEngine.handle(sensor_key, new_value)
    end

    new_timestamp = if sensor_value != nil, do: now, else: timestamp
    new_timeout = is_timeout and sensor_value == nil

    new_state = %{
      state
      | value: sensor_value || value,
        timestamp: new_timestamp,
        timed_out: new_timeout
    }

    Process.send_after(self(), :poll, poll_interval_ms)
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

  defp handle_timeout(sensor_key, last_value) do
    fallback_value =
      if String.starts_with?(sensor_key, "BTN"),
        do: 0,
        else: last_value || AudioEngine.fallback_value(sensor_key)

    Logger.info("Sending fallback: #{sensor_key} = #{fallback_value}")
    AudioEngine.handle(sensor_key, fallback_value)
    :ok
  end

  defp timeout?(last_timestamp, current_timestamp, _sensor_key)
       when is_nil(last_timestamp) or is_nil(current_timestamp) do
    false
  end

  defp timeout?(last_timestamp, current_timestamp, sensor_key) do
    time_since_last_read = current_timestamp - last_timestamp

    if time_since_last_read > @timeout_ms, do: true, else: false
  end

  defp validate(nil), do: {:error, :no_value}
  defp validate(value) when is_integer(value), do: {:ok, value}
  defp validate(_), do: {:error, :invalid_value}
end
