defmodule ElixirconfAvNetwork.Web.Live.SensorDashboardLive do
  use ElixirconfAvNetwork.Web, :live_view

  alias ElixirconfAvNetwork.Sensors.SensorRegistry

  @refresh_interval_ms 1000
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
    |> Enum.map(fn key ->
      case SensorRegistry.whereis(key) do
        %{value: value, timestamp: timestamp, timed_out: timed_out} ->
          %{
            name: key,
            value: value,
            timestamp: timestamp,
            status: if(timed_out, do: :timed_out, else: :ok)
          }

        _ ->
          %{name: key, value: nil, timestamp: nil, status: :not_found}
      end
    end)
  end

  defp format_timestamp(timestamp) do
    now = System.system_time(:millisecond)
    diff_ms = now - timestamp
    diff_sec = div(diff_ms, @refresh_interval_ms)

    if diff_sec < @max_ago_sec do
      "#{diff_sec}s ago"
    else
      DateTime.from_unix(timestamp, :millisecond)
      |> DateTime.to_string()
    end
  end
end
