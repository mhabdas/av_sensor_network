defmodule ElixirconfAvNetwork.Sensors.TemperatureConsensus do
  @moduledoc """
  Periodically collects readings from multiple temperature sensors and provides a consensus value.
  """

  use GenServer

  require Logger

  alias ElixirconfAvNetwork.Output.AudioEngine
  alias ElixirconfAvNetwork.Sensors.Sensor
  alias ElixirconfAvNetwork.Sensors.TMRVoting

  @poll_interval_ms 500
  @temp_keys ["TEMP1", "TEMP2", "TEMP3"]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  def init(_opts) do
    schedule_next_check()

    {:ok,
     %{
       consensus: nil,
       status: :initializing,
       active_sensors: 0,
       outliers: [],
       unresolved: []
     }}
  end

  def handle_info(:check_consensus, state) do
    temp1 = get_sensor_value("TEMP1")
    temp2 = get_sensor_value("TEMP2")
    temp3 = get_sensor_value("TEMP3")

    new_state =
      case TMRVoting.vote(temp1, temp2, temp3) do
        {:ok, consensus, active_sensors, outlier_indices} ->
          outliers = Enum.map(outlier_indices, &Enum.at(@temp_keys, &1 - 1))
          # Log only when transitioning TO outlier state (not when staying or recovering)
          if outliers != [] and state.outliers != outliers do
            Logger.warning("TMR: outlier detected, using 2 sensors")
          end

          send_to_audio_engine(consensus)

          %{
            state
            | consensus: consensus,
              status: :ok,
              active_sensors: active_sensors,
              outliers: outliers,
              unresolved: []
          }

        {:degraded, consensus, active_sensors, _} ->
          send_to_audio_engine(consensus)

          %{
            state
            | consensus: consensus,
              status: :degraded,
              active_sensors: active_sensors,
              outliers: [],
              unresolved: []
          }

        {:error, :no_sensors} ->
          if state.consensus != nil, do: send_to_audio_engine(state.consensus)

          %{
            state
            | consensus: nil,
              status: :error,
              active_sensors: 0,
              outliers: [],
              unresolved: []
          }

        {:error, :outlier_detected} ->
          # 2+ sensors disagree – can't determine which; use last consensus if available
          if state.consensus != nil, do: send_to_audio_engine(state.consensus)

          %{
            state
            | consensus: state.consensus,
              status: :error,
              active_sensors: 0,
              outliers: [],
              unresolved: @temp_keys
          }

        {:error, _} ->
          if state.consensus != nil, do: send_to_audio_engine(state.consensus)

          %{
            state
            | consensus: state.consensus,
              status: :error,
              active_sensors: 0,
              outliers: [],
              unresolved: []
          }
      end

    schedule_next_check()
    {:noreply, new_state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  defp schedule_next_check() do
    Process.send_after(self(), :check_consensus, @poll_interval_ms)
  end

  defp get_sensor_value(sensor_key) do
    case Sensor.read(sensor_key) do
      {:ok, value, _} -> value
      {:ok, value} -> value
      {:error, _} -> nil
      _ -> nil
    end
  end

  defp send_to_audio_engine(consensus) do
    AudioEngine.handle("TEMP", consensus)
  end
end
