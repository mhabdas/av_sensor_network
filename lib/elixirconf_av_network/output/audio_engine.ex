defmodule ElixirconfAvNetwork.Output.AudioEngine do
  alias ElixirconfAvNetwork.Output.OSCOutput
  require Logger

  @pentatonic [0, 2, 4, 7, 9]
  # Middle C
  @base_note 60

  # POT1 → frequency (pentatonic scale)
  def handle("POT1", value) do
    freq = pot_to_frequency(value)
    OSCOutput.send_message("/frequency", [freq])
  end

  # POT2 → reverb (0.0 - 1.0)
  def handle("POT2", value) do
    reverb = Float.round(value / 1023, 2)
    OSCOutput.send_message("/reverb", [reverb])
  end

  # BTN1 → note trigger
  def handle("BTN1", 1) do
    Logger.info("BTN1: 1")
    OSCOutput.send_message("/trigger", [1])
  end

  def handle("BTN1", 0) do
    OSCOutput.send_message("/trigger", [0])
  end

  # BTN2 → scale up
  def handle("BTN2", 1) do
    OSCOutput.send_message("octave", [1])
  end

  # BTN3 → scale down
  def handle("BTN3", 1) do
    OSCOutput.send_message("octave", [-1])
  end

  # Ignore other sensors for now
  def handle(_sensor, _value), do: :ok

  # Private: map POT value to pentatonic scale frequency
  defp pot_to_frequency(value) do
    # 3 octaves
    steps = length(@pentatonic) * 3
    index = round(value / 1023 * (steps - 1))
    octave = div(index, length(@pentatonic))
    degree = rem(index, length(@pentatonic))
    midi_note = @base_note + octave * 12 + Enum.at(@pentatonic, degree)
    midi_to_hz(midi_note)
  end

  # MIDI note → Hz
  defp midi_to_hz(note) do
    Float.round(440.0 * :math.pow(2, (note - 69) / 12), 2)
  end
end
