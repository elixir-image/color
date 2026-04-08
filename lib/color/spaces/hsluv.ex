defmodule Color.HSLuv do
  @moduledoc """
  HSLuv — a perceptually-uniform alternative to HSL, built on CIELUV.

  Reference: https://www.hsluv.org/ (Alexei Boronine, 2015).

  HSLuv is a cylindrical reparameterisation of `LCHuv` where `S` is
  rescaled so `S = 100` is always the maximum chroma achievable inside
  the sRGB gamut for the given `L` and `H`. Equal steps in `S` therefore
  produce perceptually similar saturation steps across the hue circle,
  unlike plain HSL where equal steps in `S` mean wildly different
  perceptual saturation for different hues.

  Channels:

  * `h ∈ [0, 360)` — hue in degrees.

  * `s ∈ [0, 100]` — saturation (0 = gray, 100 = sRGB gamut edge).

  * `l ∈ [0, 100]` — lightness.

  """

  @behaviour Color.Behaviour

  defstruct [:h, :s, :l, :alpha]

  @typedoc """
  An HSLuv colour (Boronine 2015). Hue in degrees `[0.0, 360.0)`,
  saturation and lightness as percentages `[0.0, 100.0]`. Built on
  CIELUV, perceptually uniform.
  """
  @type t :: %__MODULE__{
          h: float() | nil,
          s: float() | nil,
          l: float() | nil,
          alpha: Color.Types.alpha()
        }

  @doc """
  Converts an HSLuv color to `LCHuv`.

  ### Arguments

  * `hsluv` is a `Color.HSLuv` struct.

  ### Returns

  * A `Color.LCHuv` struct (D65/2°).

  ### Examples

      iex> {:ok, lch} = Color.HSLuv.to_lchuv(%Color.HSLuv{h: 12.177, s: 100.0, l: 53.237})
      iex> {Float.round(lch.l, 2), Float.round(lch.c, 2), Float.round(lch.h, 2)}
      {53.24, 179.04, 12.18}

  """
  def to_lchuv(%__MODULE__{h: h, s: s, l: l, alpha: alpha}) do
    cond do
      l > 100 - 1.0e-7 ->
        {:ok, %Color.LCHuv{l: 100.0, c: 0.0, h: h, alpha: alpha}}

      l < 1.0e-8 ->
        {:ok, %Color.LCHuv{l: 0.0, c: 0.0, h: h, alpha: alpha}}

      true ->
        mx = Color.HSLuv.Gamut.max_chroma_for_lh(l, h)
        c = mx * s / 100
        {:ok, %Color.LCHuv{l: l, c: c, h: h, alpha: alpha}}
    end
  end

  @doc """
  Converts an `LCHuv` color to HSLuv.

  ### Arguments

  * `lchuv` is a `Color.LCHuv` struct.

  ### Returns

  * A `Color.HSLuv` struct.

  """
  def from_lchuv(%Color.LCHuv{l: l, c: c, h: h, alpha: alpha}) do
    cond do
      l > 100 - 1.0e-7 ->
        {:ok, %__MODULE__{h: h, s: 0.0, l: 100.0, alpha: alpha}}

      l < 1.0e-8 ->
        {:ok, %__MODULE__{h: h, s: 0.0, l: 0.0, alpha: alpha}}

      true ->
        mx = Color.HSLuv.Gamut.max_chroma_for_lh(l, h)
        s = c / mx * 100
        {:ok, %__MODULE__{h: h, s: s, l: l, alpha: alpha}}
    end
  end

  @doc """
  Converts an HSLuv color to CIE `XYZ` via `LCHuv`.

  """
  def to_xyz(%__MODULE__{} = hsluv) do
    with {:ok, lch} <- to_lchuv(hsluv), do: Color.LCHuv.to_xyz(lch)
  end

  @doc """
  Converts a CIE `XYZ` color to HSLuv via `LCHuv`.

  """
  def from_xyz(%Color.XYZ{} = xyz) do
    with {:ok, lch} <- Color.LCHuv.from_xyz(xyz), do: from_lchuv(lch)
  end
end
