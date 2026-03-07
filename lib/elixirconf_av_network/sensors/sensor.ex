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
  @pot_disconnected_value 30
  @light_disconnected_value 5
  @poll_send_after_ms 100

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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

  @doc """
  Returns %{value: value, timestamp: timestamp, timed_out: boolean} for the dashboard.
  """
  def get_status(pid) when is_pid(pid) do
    GenServer.call(pid, :get_status)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

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
      timed_out: false,
      suspect: false,
      suspect_reason: nil
    }

    Process.send_after(self(), :poll, @poll_send_after_ms)

    {:ok, state}
  end

  def handle_call(:read, _from, state) do
    {:reply, {:ok, state.value, state.timestamp}, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply,
     %{
       value: state.value,
       timestamp: state.timestamp,
       timed_out: state.timed_out,
       suspect: state.suspect,
       suspect_reason: state.suspect_reason
     }, state}
  end

  def handle_info(:poll, state) do
    sensor_value = fetch_sensor_value(state.data_source, state.sensor_key)
    now = System.system_time(:millisecond)
    is_timeout = timeout?(state.timestamp, now, state.sensor_key)
    {suspect, suspect_reason} = check_suspect(state, sensor_value)

    maybe_handle_timeout(state, sensor_value, is_timeout)
    if healthy?(suspect, is_timeout), do: maybe_send_value(state, sensor_value)

    new_state = build_poll_state(state, sensor_value, now, suspect, suspect_reason, is_timeout)
    Process.send_after(self(), :poll, state.poll_interval_ms)
    {:noreply, new_state}
  end

  # ---------------------------------------------------------------------------
  # Data fetching
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Health & suspect detection
  # ---------------------------------------------------------------------------

  defp timeout?(last_timestamp, current_timestamp, _sensor_key)
       when is_nil(last_timestamp) or is_nil(current_timestamp) do
    false
  end

  defp timeout?(last_timestamp, current_timestamp, _sensor_key) do
    time_since_last_read = current_timestamp - last_timestamp
    time_since_last_read > @timeout_ms
  end

  defp detect_suspect("POT" <> _, value)
       when is_integer(value) and value < @pot_disconnected_value do
    {:suspect, :disconnected}
  end

  defp detect_suspect("LIGHT" <> _, value)
       when is_integer(value) and value < @light_disconnected_value do
    {:suspect, :disconnected}
  end

  # TODO: Implement temperature suspect detection
  defp detect_suspect("TEMP" <> _, _value) do
    :ok
  end

  defp detect_suspect(_, _), do: :ok

  defp check_suspect(_state, nil) do
    {false, nil}
  end

  defp check_suspect(state, sensor_value) do
    case detect_suspect(state.sensor_key, sensor_value) do
      {:suspect, reason} ->
        unless state.suspect, do: Logger.warning("#{state.sensor_key} suspect: #{reason}")
        {true, reason}

      :ok ->
        if state.suspect, do: Logger.info("#{state.sensor_key} recovered from suspect")
        {false, nil}
    end
  end

  defp healthy?(suspect, is_timeout), do: not suspect and not is_timeout

  # ---------------------------------------------------------------------------
  # Timeout handling
  # ---------------------------------------------------------------------------

  defp maybe_handle_timeout(%{timed_out: false} = state, _sensor_value, true) do
    Logger.warning("TIMEOUT TRIGGERED for #{state.sensor_key}!")
    handle_timeout(state.sensor_key, state.value)
  end

  defp maybe_handle_timeout(%{timed_out: true} = state, sensor_value, _is_timeout)
       when not is_nil(sensor_value) do
    Logger.warning("TIMEOUT CLEARED for #{state.sensor_key}!")
  end

  defp maybe_handle_timeout(_state, _sensor_value, _is_timeout), do: :ok

  defp handle_timeout(sensor_key = "BTN" <> _, _last_value) do
    Logger.info("Sending fallback: #{sensor_key} = 0")
    AudioEngine.handle(sensor_key, 0)
    :ok
  end

  defp handle_timeout(sensor_key, last_value) do
    fallback_value = last_value || AudioEngine.fallback_value(sensor_key)
    Logger.info("Sending fallback: #{sensor_key} = #{fallback_value}")
    AudioEngine.handle(sensor_key, fallback_value)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Value validation & output
  # ---------------------------------------------------------------------------

  defp maybe_send_value(state, sensor_value) do
    with {:ok, new_value} <- validate(sensor_value),
         true <- new_value != state.value do
      AudioEngine.handle(state.sensor_key, new_value)
    end
  end

  defp validate(nil), do: {:error, :no_value}
  defp validate(value) when is_integer(value), do: {:ok, value}
  defp validate(_), do: {:error, :invalid_value}

  # ---------------------------------------------------------------------------
  # State
  # ---------------------------------------------------------------------------

  defp build_poll_state(state, sensor_value, now, suspect, suspect_reason, is_timeout) do
    is_healthy = healthy?(suspect, is_timeout)

    %{
      state
      | value: if(is_healthy and sensor_value != nil, do: sensor_value, else: state.value),
        timestamp: if(sensor_value != nil, do: now, else: state.timestamp),
        timed_out: is_timeout and sensor_value == nil,
        suspect: suspect,
        suspect_reason: suspect_reason
    }
  end
end
