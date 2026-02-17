defmodule ElixirconfAvNetwork.Hardware.ArduinoPortDetectorService do
  @moduledoc """
  Caches port detection result so multiple ArduinoConnections share one detect() run.
  Runs detection in a Task to avoid blocking the GenServer (and causing timeouts).
  """
  use GenServer

  require Logger

  @timeout 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns port for the given role. Blocks until detection completes (first call)."
  def get_port(role) do
    GenServer.call(__MODULE__, {:get_port, role}, @timeout)
  end

  @impl true
  def init(_opts) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:get_port, role}, from, nil) do
    task = Task.async(fn -> ElixirconfAvNetwork.Hardware.ArduinoPortDetector.detect() end)
    ref = Process.monitor(task.pid)
    {:noreply, %{task: task, monitor_ref: ref, pending: [{role, from}]}}
  end

  def handle_call({:get_port, role}, from, %{task: _} = state) do
    pending = [{role, from} | state.pending]
    {:noreply, %{state | pending: pending}}
  end

  def handle_call({:get_port, role}, _from, %{interactive: _} = result) do
    port = Map.get(result, role)
    {:reply, {:ok, port}, result}
  end

  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}, monitor_ref: mon_ref, pending: pending}) do
    Process.demonitor(mon_ref, [:flush])

    {result_map, error} =
      case result do
        {:ok, %{interactive: i, environmental: e}} -> {%{interactive: i, environmental: e}, nil}
        {:error, reason} -> {nil, reason}
      end

    if error, do: Logger.warning("ArduinoPortDetector failed: #{inspect(error)}")

    for {role, from} <- Enum.reverse(pending) do
      port = result_map && Map.get(result_map, role)
      GenServer.reply(from, if(result_map, do: {:ok, port}, else: {:error, error}))
    end

    {:noreply, result_map || nil}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{task: _, pending: pending}) do
    Logger.warning("ArduinoPortDetector task crashed: #{inspect(reason)}")

    for {_role, from} <- pending do
      GenServer.reply(from, {:error, :detection_failed})
    end

    {:noreply, nil}
  end
end
