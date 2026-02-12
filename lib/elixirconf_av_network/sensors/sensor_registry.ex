defmodule ElixirconfAvNetwork.Sensors.SensorRegistry do
  @moduledoc """
  Registry for dynamically started Sensor processes.
  Keys: sensor name (e.g. "POT1", "BTN1").
  """

  def via_tuple(sensor_key) do
    {:via, Registry, {__MODULE__, sensor_key}}
  end

  def whereis(sensor_key) do
    Registry.whereis_name({__MODULE__, sensor_key})
  end

  def registered_keys do
    spec = [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}]

    Registry.select(__MODULE__, spec)
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
  end
end
