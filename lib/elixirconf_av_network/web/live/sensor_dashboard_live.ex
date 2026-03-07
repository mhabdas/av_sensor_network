defmodule ElixirconfAvNetwork.Web.Live.SensorDashboardLive do
  use ElixirconfAvNetwork.Web, :live_view

  alias ElixirconfAvNetwork.Sensors.Sensor
  alias ElixirconfAvNetwork.Sensors.SensorRegistry
  alias ElixirconfAvNetwork.Sensors.TemperatureConsensus

  @refresh_interval_ms 200
  @max_ago_sec 60
  @max_concurrency 16
  @timeout_ms 2_000

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval_ms, self(), :refresh)
    end

    {:ok, assign(socket, :sensors, fetch_sensor_data())}
  end

  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :sensors, fetch_sensor_data())}
  end

  # ---------------------------------------------------------------------------
  # Data fetching
  # ---------------------------------------------------------------------------

  defp fetch_sensor_data do
    {outliers, unresolved} = get_temp_consensus_status()

    sensors =
      SensorRegistry.registered_keys()
      |> Task.async_stream(&fetch_sensor_status/1,
        max_concurrency: @max_concurrency,
        timeout: @timeout_ms
      )
      |> Enum.flat_map(fn
        {:ok, result} -> [result]
        {:exit, _} -> []
      end)

    Enum.map(sensors, fn sensor ->
      cond do
        sensor.name in unresolved -> %{sensor | status: :unresolved}
        sensor.name in outliers -> %{sensor | status: :outlier}
        true -> sensor
      end
    end)
  end

  defp get_temp_consensus_status do
    case Process.whereis(TemperatureConsensus) do
      nil ->
        {[], []}

      pid ->
        try do
          status = TemperatureConsensus.get_status(pid)
          outliers = Map.get(status, :outliers, [])
          unresolved = Map.get(status, :unresolved, [])
          {outliers, unresolved}
        rescue
          _ -> {[], []}
        end
    end
  end

  defp fetch_sensor_status(key) do
    case SensorRegistry.whereis(key) do
      :undefined ->
        %{name: key, value: nil, timestamp: nil, status: :not_found}

      pid ->
        status = Sensor.get_status(pid)

        %{
          name: key,
          value: status.value,
          timestamp: status.timestamp,
          status: status_atom(status),
          suspect_reason: status.suspect_reason
        }
    end
  end

  defp status_atom(%{timed_out: true}), do: :timed_out
  defp status_atom(%{suspect: true}), do: :suspect
  defp status_atom(_), do: :ok

  # :outlier is set from TemperatureConsensus, not from Sensor

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(timestamp) do
    now = System.system_time(:millisecond)
    diff_ms = now - timestamp
    diff_sec = div(diff_ms, 1000)

    if diff_sec < @max_ago_sec do
      "#{diff_sec}s ago"
    else
      case DateTime.from_unix(timestamp, :millisecond) do
        {:ok, dt} -> DateTime.to_string(dt)
        {:error, _} -> "-"
      end
    end
  end
end
