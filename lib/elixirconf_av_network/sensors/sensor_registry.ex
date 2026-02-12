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
    Registry.select(__MODULE__, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(&hd/1)
    |> Enum.uniq()
  end
end
