defmodule ElixirconfAvNetwork.Output.AudioEngine do
  alias ElixirconfAvNetwork.Output.OSCOutput
  require Logger

  # C3
  @base_note 48

  # POT1 → release time
  @spec handle(any(), any()) :: :ok | {:error, atom()}
  def handle("POT1", value) do
    release = Float.round(50 + value / 1023 * 800, 1)
    OSCOutput.send_message("/release", [release])
  end

  # POT2 → filter (light/dark)
  def handle("POT2", value) do
    x = value / 1023
    # ~150..5000
    cutoff = 150 + :math.pow(x, 2.2) * 4850
    OSCOutput.send_message("/filter_cutoff", [cutoff])
  end

  # BTN1 → note trigger (C)
  def handle("BTN1", 1) do
    freq = midi_to_hz(@base_note)
    OSCOutput.send_message("/note_on", [freq])
  end

  # BTN2 → note trigger (Eb)
  def handle("BTN2", 1) do
    freq = midi_to_hz(@base_note + 7)
    OSCOutput.send_message("/note_on", [freq])
  end

  # BTN3 → note trigger (G)
  def handle("BTN3", 1) do
    freq = midi_to_hz(@base_note + 10)
    OSCOutput.send_message("/note_on", [freq])
  end

  def handle("BTN1", 0), do: OSCOutput.send_message("/note_off", [0])
  def handle("BTN2", 0), do: OSCOutput.send_message("/note_off", [0])
  def handle("BTN3", 0), do: OSCOutput.send_message("/note_off", [0])

  # LIGHT1 → velocity
  def handle("LIGHT1", value) do
    velocity = Float.round(value / 1023, 2)
    OSCOutput.send_message("/velocity", [velocity])
  end

  # LIGHT2 -> LFO rate
  def handle("LIGHT2", value) do
    rate = Float.round(0.1 + value / 1023 * 9.9, 2)
    OSCOutput.send_message("/lfo_rate", [rate])
    OSCOutput.send_message("/lfo_depth", [10.0])
  end

  # TEMP1 -> additional cutoff
  def handle("TEMP1", value) do
    cutoff =
      Float.round(500 + (value - 40) * 87.5, 1)
      |> max(500.0)
      |> min(4000.0)

    OSCOutput.send_message("/temp_cutoff", [cutoff])
  end

  # TEMP2 -> reverb
  def handle("TEMP2", value) do
    reverb =
      Float.round((value - 40) / 40, 2)
      |> max(0.0)
      |> min(1.0)

    OSCOutput.send_message("/reverb", [reverb])
  end

  # Ignore other sensors for now
  def handle(_sensor, _value), do: :ok

  @doc """
  Fallback value for sensors that are not connected.
  """
  @spec fallback_value(<<_::24, _::_*8>>) :: 0 | 50 | 400 | 512
  def fallback_value("BTN" <> _), do: 0
  def fallback_value("POT1"), do: 400
  def fallback_value("POT2"), do: 512
  def fallback_value("TEMP" <> _), do: 50
  def fallback_value("LIGHT1"), do: 512
  def fallback_value("LIGHT2"), do: 0

  # MIDI note → Hz
  defp midi_to_hz(note) do
    Float.round(440.0 * :math.pow(2, (note - 69) / 12), 2)
  end
end
