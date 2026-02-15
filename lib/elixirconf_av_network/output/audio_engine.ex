defmodule ElixirconfAvNetwork.Output.AudioEngine do
  alias ElixirconfAvNetwork.Output.OSCOutput
  require Logger

  # C3
  @base_note 48

  # POT1 → pitch bend / vibrato
  def handle("POT1", value) do
    bend = Float.round(value / 1023 * 2 - 1, 3)
    OSCOutput.send_message("/pitch_bend", [bend])
  end

  # POT2 → filter (light/dark)
  def handle("POT2", value) do
    cutoff = Float.round(200 + value / 1023 * 7800, 1)
    OSCOutput.send_message("/filter_cutoff", [cutoff])
  end

  # BTN1 → note trigger (C)
  def handle("BTN1", 1) do
    freq = midi_to_hz(@base_note)
    OSCOutput.send_message("/note_on", [freq])
  end

  # BTN2 → note trigger (Eb)
  def handle("BTN2", 1) do
    freq = midi_to_hz(@base_note + 3)
    OSCOutput.send_message("/note_on", [freq])
  end

  # BTN3 → note trigger (G)
  def handle("BTN3", 1) do
    freq = midi_to_hz(@base_note + 7)
    OSCOutput.send_message("/note_on", [freq])
  end

  def handle("BTN1", 0), do: OSCOutput.send_message("/note_off", [0])
  def handle("BTN2", 0), do: OSCOutput.send_message("/note_off", [0])
  def handle("BTN3", 0), do: OSCOutput.send_message("/note_off", [0])

  # Ignore other sensors for now
  def handle(_sensor, _value), do: :ok

  # MIDI note → Hz
  defp midi_to_hz(note) do
    Float.round(440.0 * :math.pow(2, (note - 69) / 12), 2)
  end
end
