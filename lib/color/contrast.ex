defmodule Color.Contrast do
  @moduledoc """
  Contrast and luminance computations.

  * `relative_luminance/1` — the `Y` component of an sRGB color as
    defined by WCAG 2.x (applies the sRGB inverse companding then takes
    `0.2126·R + 0.7152·G + 0.0722·B`).

  * `wcag_ratio/2` — WCAG 2.x contrast ratio,
    `(L1 + 0.05) / (L2 + 0.05)` where `L1 ≥ L2`. Result range
    `[1.0, 21.0]`.

  * `wcag_level/2` — classifies a pair as `:aaa`, `:aaa_large`, `:aa`,
    `:aa_large`, or `:fail` for the common normal-text / large-text
    thresholds.

  * `apca/2` — the Accessible Perceptual Contrast Algorithm (APCA
    W3 0.1.9), the successor to WCAG 2 proposed for CSS Color 5.
    Returns a signed `L_c` value roughly in `[-108, 106]`.

  * `pick_contrasting/3` — given a background and two candidate
    foregrounds, pick the one with the higher contrast against the
    background.

  All inputs may be anything accepted by `Color.new/1`.

  """

  @doc """
  Returns the WCAG 2.x relative luminance of a color — the `Y`
  component of its linear sRGB, on the `[0, 1]` scale.

  ### Arguments

  * `color` is anything accepted by `Color.new/1`.

  ### Returns

  * A float in `[0, 1]`.

  ### Examples

      iex> Color.Contrast.relative_luminance("white")
      1.0

      iex> Color.Contrast.relative_luminance("black")
      0.0

      iex> Float.round(Color.Contrast.relative_luminance("red"), 4)
      0.2126

  """
  @spec relative_luminance(Color.input()) :: float()
  def relative_luminance(color) do
    {:ok, srgb} = Color.convert(color, Color.SRGB)

    r = Color.Conversion.Lindbloom.srgb_inverse_compand(srgb.r)
    g = Color.Conversion.Lindbloom.srgb_inverse_compand(srgb.g)
    b = Color.Conversion.Lindbloom.srgb_inverse_compand(srgb.b)

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  @doc """
  Returns the WCAG 2.x contrast ratio between two colors.

  ### Arguments

  * `a` is any color accepted by `Color.new/1`.

  * `b` is any color accepted by `Color.new/1`.

  ### Returns

  * A float in `[1.0, 21.0]`. `1.0` means no contrast; `21.0` is the
    maximum (black on white or white on black).

  ### Examples

      iex> Float.round(Color.Contrast.wcag_ratio("white", "black"), 2)
      21.0

      iex> Float.round(Color.Contrast.wcag_ratio("#777", "white"), 2)
      4.48

  """
  @spec wcag_ratio(Color.input(), Color.input()) :: float()
  def wcag_ratio(a, b) do
    la = relative_luminance(a)
    lb = relative_luminance(b)
    {lighter, darker} = if la >= lb, do: {la, lb}, else: {lb, la}
    (lighter + 0.05) / (darker + 0.05)
  end

  @doc """
  Classifies a WCAG contrast ratio into the accessibility grade it
  meets for normal and large text.

  The thresholds are:

  * **AAA** — `7.0` normal text, `4.5` large text.

  * **AA** — `4.5` normal text, `3.0` large text.

  ### Arguments

  * `a` is any color accepted by `Color.new/1`.

  * `b` is any color accepted by `Color.new/1`.

  ### Returns

  * One of `:aaa`, `:aaa_large`, `:aa`, `:aa_large`, `:fail`.

  ### Examples

      iex> Color.Contrast.wcag_level("black", "white")
      :aaa

      iex> Color.Contrast.wcag_level("#777", "white")
      :aa_large

  """
  @spec wcag_level(Color.input(), Color.input()) ::
          :aaa | :aaa_large | :aa_large | :fail
  def wcag_level(a, b) do
    ratio = wcag_ratio(a, b)

    cond do
      ratio >= 7.0 -> :aaa
      ratio >= 4.5 -> :aaa_large
      ratio >= 3.0 -> :aa_large
      true -> :fail
    end
  end

  @doc """
  Returns the APCA `L_c` contrast value between a text colour and a
  background colour.

  APCA is directional: swapping the arguments can change the
  magnitude and sign of the result. Positive values mean the text is
  darker than the background (normal polarity); negative values mean
  lighter text on a darker background (reverse polarity).

  Values are roughly in the range `[-108, 106]`. The rough thresholds
  suggested by the APCA spec are:

  * `|Lc| ≥ 90` — body text under the WCAG 3 "fluent" rating.

  * `|Lc| ≥ 75` — body text, content.

  * `|Lc| ≥ 60` — content, large headlines.

  * `|Lc| ≥ 45` — large / bold text.

  * `|Lc| ≥ 30` — non-text ornamental.

  Reference: https://github.com/Myndex/apca-w3 (APCA-W3 0.1.9).

  ### Arguments

  * `text` is the foreground colour — anything accepted by `Color.new/1`.

  * `background` is the background colour.

  ### Returns

  * A signed float.

  ### Examples

      iex> Float.round(Color.Contrast.apca("black", "white"), 1)
      106.0

      iex> Float.round(Color.Contrast.apca("white", "black"), 1)
      -107.9

  """
  @spec apca(Color.input(), Color.input()) :: float()
  def apca(text, background) do
    yt = apca_y(text)
    yb = apca_y(background)

    # Soft-clip the low end to avoid divergence near black.
    yt = if yt < 0.022, do: yt + :math.pow(0.022 - yt, 1.414), else: yt
    yb = if yb < 0.022, do: yb + :math.pow(0.022 - yb, 1.414), else: yb

    cond do
      abs(yb - yt) < 0.0005 ->
        0.0

      yb > yt ->
        # Normal polarity — darker text on lighter background.
        sapc = (:math.pow(yb, 0.56) - :math.pow(yt, 0.57)) * 1.14

        cond do
          sapc < 0.1 -> 0.0
          true -> (sapc - 0.027) * 100
        end

      true ->
        # Reverse polarity — lighter text on darker background.
        sapc = (:math.pow(yb, 0.65) - :math.pow(yt, 0.62)) * 1.14

        cond do
          sapc > -0.1 -> 0.0
          true -> (sapc + 0.027) * 100
        end
    end
  end

  @doc """
  Picks the candidate that gives the higher WCAG contrast against the
  background.

  ### Arguments

  * `background` is any color accepted by `Color.new/1`.

  * `candidates` is a list of colors accepted by `Color.new/1`.
    Defaults to `["white", "black"]`.

  ### Returns

  * `{:ok, color_struct}` where `color_struct` is the chosen candidate
    as a `Color.SRGB` struct.

  ### Examples

      iex> {:ok, chosen} = Color.Contrast.pick_contrasting("white")
      iex> Color.SRGB.to_hex(chosen)
      "#000000"

      iex> {:ok, chosen} = Color.Contrast.pick_contrasting("#333")
      iex> Color.SRGB.to_hex(chosen)
      "#ffffff"

      iex> {:ok, chosen} = Color.Contrast.pick_contrasting("red", ["yellow", "darkblue"])
      iex> Color.SRGB.to_hex(chosen)
      "#00008b"

  """
  @spec pick_contrasting(Color.input(), [Color.input()]) ::
          {:ok, Color.SRGB.t()} | {:error, Exception.t()}
  def pick_contrasting(background, candidates \\ ["white", "black"]) do
    with {:ok, bg} <- Color.convert(background, Color.SRGB) do
      {chosen, _ratio} =
        candidates
        |> Enum.map(fn candidate ->
          {:ok, srgb} = Color.convert(candidate, Color.SRGB)
          {srgb, wcag_ratio(bg, srgb)}
        end)
        |> Enum.max_by(fn {_, ratio} -> ratio end)

      {:ok, chosen}
    end
  end

  # APCA uses its own luminance formula with a fixed 2.4 exponent
  # (not the full sRGB piecewise EOTF) and slightly different weights.
  defp apca_y(color) do
    {:ok, srgb} = Color.convert(color, Color.SRGB)
    r = :math.pow(clamp01(srgb.r), 2.4)
    g = :math.pow(clamp01(srgb.g), 2.4)
    b = :math.pow(clamp01(srgb.b), 2.4)
    0.2126729 * r + 0.7151522 * g + 0.0721750 * b
  end

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
