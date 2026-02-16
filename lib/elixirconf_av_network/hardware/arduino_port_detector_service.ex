defmodule ElixirconfAvNetwork.Hardware.ArduinoPortDetectorService do
  @moduledoc """
  Caches port detection result so multiple ArduinoConnections share one detect() run.
  Runs detection on first request; subsequent calls get cached result.
  """
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns port for the given role. Blocks until detection completes (first call)."
  def get_port(role) do
    GenServer.call(__MODULE__, {:get_port, role}, 30_000)
  end

  @impl true
  def init(_opts) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:get_port, role}, _from, nil) do
    case ElixirconfAvNetwork.Hardware.ArduinoPortDetector.detect() do
      {:ok, %{interactive: inter, environmental: env}} ->
        result = %{interactive: inter, environmental: env}
        port = Map.get(result, role)
        {:reply, {:ok, port}, result}

      {:error, reason} ->
        Logger.warning("ArduinoPortDetector failed: #{inspect(reason)}")
        {:reply, {:error, reason}, nil}
    end
  end

  def handle_call({:get_port, role}, _from, result) when not is_nil(result) do
    port = Map.get(result, role)
    {:reply, {:ok, port}, result}
  end
end
