defmodule ElixirconfAvNetwork.Hardware.ProtocolJson do
  @moduledoc """
  JSON protocol for hardware (e.g. Arduino over UART).
  """

  def parse_sensor_data(data) do
    case Jason.decode(data) do
      {:ok, %{"sensor" => sensor, "value" => value}} ->
        {:ok, {sensor, value}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
