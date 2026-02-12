defmodule ElixirconfAvNetwork.Hardware.Protocol do
  @moduledoc """
  Binary protocol for hardware (e.g. Arduino over UART).

  Frame format: `<<0xFF, sensor_id, value::16, checksum>>` (5 bytes).
  Checksum = (sensor_id + high_byte(value) + low_byte(value)) &&& 0xFF.

  Use `parse_sensor_data/1` for a single 5-byte frame, or `extract_frame_from_buffer/1`
  when reading a stream (handles resync after errors or garbage).
  """

  import Bitwise

  @frame_size 5
  @start_byte 0xFF

  @pot1 0x01
  @pot2 0x02
  @btn1 0x10
  @btn2 0x11
  @btn3 0x12

  @spec sensor_name(any()) :: <<_::32>>
  def sensor_name(@pot1), do: "POT1"
  def sensor_name(@pot2), do: "POT2"
  def sensor_name(@btn1), do: "BTN1"
  def sensor_name(@btn2), do: "BTN2"
  def sensor_name(@btn3), do: "BTN3"

  @spec extract_frame_from_buffer(bitstring()) ::
          :incomplete
          | {:error, :checksum_mismatch, binary()}
          | {:ok, {:ok, String.t(), non_neg_integer()}, binary()}
  @doc """
  Extracts one frame from a binary buffer (e.g. accumulated UART data). Handles resync:
  - Drops bytes until a start byte (0xFF) is found, then tries to parse a full frame.
  - On checksum error, drops the first byte and retries (call again with returned rest).

  Returns:
  - `{:ok, {:ok, sensor_name, value}, rest}` – valid frame and remaining buffer
  - `{:error, :checksum_mismatch, rest}` – bad checksum; use `rest` as new buffer and call again
  - `:incomplete` – need more data; keep the buffer and append the next chunk
  """
  def extract_frame_from_buffer(buffer) when byte_size(buffer) < @frame_size do
    :incomplete
  end

  def extract_frame_from_buffer(buffer) do
    case find_start_and_parse(buffer) do
      {:ok, result, rest} -> {:ok, result, rest}
      {:error, rest} -> {:error, :checksum_mismatch, rest}
      :incomplete -> :incomplete
    end
  end

  defp find_start_and_parse(
         <<@start_byte, sensor_id, value::little-16, checksum, rest::binary>> = buffer
       ) do
    expected = calculate_checksum(sensor_id, value)

    if checksum == expected do
      {:ok, {:ok, sensor_name(sensor_id), value}, rest}
    else
      {:error, binary_part(buffer, 1, byte_size(buffer) - 1)}
    end
  end

  defp find_start_and_parse(buffer) do
    case :binary.match(buffer, <<@start_byte>>) do
      :nomatch ->
        :incomplete

      {pos, _len} ->
        rest = binary_part(buffer, pos, byte_size(buffer) - pos)
        if byte_size(rest) >= @frame_size, do: find_start_and_parse(rest), else: :incomplete
    end
  end

  defp calculate_checksum(sensor_id, value) do
    sensor_id + (value >>> 8) + (value &&& 0xFF) &&& 0xFF
  end
end
