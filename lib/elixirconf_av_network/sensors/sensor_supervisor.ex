defmodule ElixirconfAvNetwork.Sensors.SensorSupervisor do
  @moduledoc """
  DynamicSupervisor for sensor processes. Sensors are started when data arrives
  from ArduinoConnection for a new sensor key.
  """
  use DynamicSupervisor

  alias ElixirconfAvNetwork.Sensors.Sensor
  alias ElixirconfAvNetwork.Sensors.SensorRegistry

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a Sensor process for the given sensor_key if it doesn't exist yet.
  Idempotent – does nothing when the Sensor is already running.
  """
  def start_sensor_if_needed(sensor_key) when is_binary(sensor_key) do
    case SensorRegistry.whereis(sensor_key) do
      :undefined ->
        start_sensor(sensor_key)

      _pid ->
        :ok
    end
  end

  def start_sensor_if_needed(sensor_key) when is_atom(sensor_key) do
    start_sensor_if_needed(to_string(sensor_key))
  end

  @doc """
  Returns list of registered sensor keys.
  """
  def registered_sensors do
    SensorRegistry.registered_keys()
  end

  def sensor_names do
    Enum.map(registered_sensors(), &SensorRegistry.via_tuple/1)
  end

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp start_sensor(sensor_key) do
    child_spec = {
      Sensor,
      [
        sensor_key: sensor_key,
        data_source: ElixirconfAvNetwork.Hardware.ArduinoConnection.data_source_name(),
        poll_interval_ms: 1000,
        name: SensorRegistry.via_tuple(sensor_key)
      ]
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
