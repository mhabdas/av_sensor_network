defmodule ElixirconfAvNetwork.Sensors.TMRVoting do
  @moduledoc """
  Triple Modular Redundancy voting for temperature sensors.
  Detects outliers and provides consensus value.
  Supports 1–3 sensors; nil means sensor unavailable.
  """

  require Logger

  # Max allowed spread (max - min) between sensor values for agreement
  @agreement_threshold 5

  def vote(temp1, temp2, temp3) do
    temps = [temp1, temp2, temp3]
    values = Enum.reject(temps, &is_nil/1)
    valid? = Enum.all?(temps, &(is_integer(&1) or is_nil(&1)))

    case {valid?, values} do
      {false, _} ->
        Logger.warning("TMR: invalid sensor input")
        {:error, :invalid_input}

      {true, []} ->
        Logger.warning("TMR: no sensors available")
        {:error, :no_sensors}

      {true, [_, _, _]} ->
        vote_three(temps)

      {true, [a, b]} ->
        {:degraded, trunc((a + b) / 2), 2, []}

      {true, [_]} ->
        vote_one(values)
    end
  end

  defp vote_three([_t1, _t2, _t3] = orig) do
    [a, b, c] = Enum.sort(orig)
    spread = c - a
    pair = outlier_pair(a, b, c)

    case {spread <= @agreement_threshold, pair} do
      {true, _} ->
        {:ok, trunc((a + b + c) / 3), 3, []}

      {false, {:ok, [^a, ^b]}} ->
        {:ok, trunc((a + b) / 2), 2, [outlier_index(orig, c)]}

      {false, {:ok, [^b, ^c]}} ->
        {:ok, trunc((b + c) / 2), 2, [outlier_index(orig, a)]}

      {false, :error} ->
        {:error, :outlier_detected}
    end
  end

  defp outlier_index([v1, _v2, _v3], value) when v1 == value, do: 1
  defp outlier_index([_v1, v2, _v3], value) when v2 == value, do: 2
  defp outlier_index([_v1, _v2, v3], value) when v3 == value, do: 3

  defp outlier_pair(a, b, c) do
    case {c - b > @agreement_threshold and b - a <= @agreement_threshold,
          b - a > @agreement_threshold and c - b <= @agreement_threshold} do
      {true, false} -> {:ok, [a, b]}
      {false, true} -> {:ok, [b, c]}
      _ -> :error
    end
  end

  defp vote_one([v]) do
    Logger.warning("TMR: only 1 sensor available")
    {:degraded, v, 1, []}
  end
end
