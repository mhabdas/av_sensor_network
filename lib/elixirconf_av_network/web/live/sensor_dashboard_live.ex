defmodule ElixirconfAvNetwork.Web.Live.SensorDashboardLive do
  use ElixirconfAvNetwork.Web, :live_view

  alias ElixirconfAvNetwork.Sensors.Sensor
  alias ElixirconfAvNetwork.Sensors.SensorRegistry

  @refresh_interval_ms 200
  @max_ago_sec 60

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval_ms, self(), :refresh)
    end

    {:ok, assign(socket, :sensors, fetch_sensor_data())}
  end

  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :sensors, fetch_sensor_data())}
  end

  def fetch_sensor_data do
    SensorRegistry.registered_keys()
    |> Task.async_stream(
      fn key ->
        case SensorRegistry.whereis(key) do
          :undefined ->
            %{name: key, value: nil, timestamp: nil, status: :not_found}

          pid ->
            status = Sensor.get_status(pid)

            %{
              name: key,
              value: status.value,
              timestamp: status.timestamp,
              status: if(status.timed_out, do: :timed_out, else: :ok)
            }
        end
      end,
      max_concurrency: 16,
      timeout: 2_000
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _} -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_timestamp(nil) do
    "-"
  end

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
