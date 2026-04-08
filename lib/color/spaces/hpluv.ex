defmodule Color.HPLuv do
  @moduledoc """
  HPLuv — the "pastel" sibling of HSLuv.

  Where HSLuv lets `S = 100` reach the full sRGB gamut boundary (which
  gives different chromas at different hues), HPLuv rescales so that
  `S = 100` is the largest chroma achievable at the given `L` at ALL
  hues. This means HPLuv cannot represent the most saturated sRGB
  colours at any given lightness, but any `HPLuv(h, 100, l)` triple is
  achromatically consistent across hues — useful for "pastel" palettes.

  Reference: https://www.hsluv.org/ (Alexei Boronine).

  """

  @behaviour Color.Behaviour

  defstruct [:h, :s, :l, :alpha]

  @typedoc """
  An HPLuv colour. Like HSLuv but with the chroma component clipped
  to the largest pastel-friendly chroma at the given lightness.
  Hue in degrees `[0.0, 360.0)`, saturation and lightness as
  percentages `[0.0, 100.0]`.
  """
  @type t :: %__MODULE__{
          h: float() | nil,
          s: float() | nil,
          l: float() | nil,
          alpha: Color.Types.alpha()
        }

  @doc """
  Converts an HPLuv color to `LCHuv`.

  ### Arguments

  * `hpluv` is a `Color.HPLuv` struct.

  ### Returns

  * A `Color.LCHuv` struct.

  ### Examples

      iex> {:ok, lch} = Color.HPLuv.to_lchuv(%Color.HPLuv{h: 0.0, s: 0.0, l: 50.0})
      iex> {Float.round(lch.l, 2), Float.round(lch.c, 2)}
      {50.0, 0.0}

  """
  def to_lchuv(%__MODULE__{h: h, s: s, l: l, alpha: alpha}) do
    cond do
      l > 100 - 1.0e-7 ->
        {:ok, %Color.LCHuv{l: 100.0, c: 0.0, h: h, alpha: alpha}}

      l < 1.0e-8 ->
        {:ok, %Color.LCHuv{l: 0.0, c: 0.0, h: h, alpha: alpha}}

      true ->
        mx = Color.HSLuv.Gamut.max_safe_chroma_for_l(l)
        c = mx * s / 100
        {:ok, %Color.LCHuv{l: l, c: c, h: h, alpha: alpha}}
    end
  end

  @doc """
  Converts an `LCHuv` color to HPLuv.

  """
  def from_lchuv(%Color.LCHuv{l: l, c: c, h: h, alpha: alpha}) do
    cond do
      l > 100 - 1.0e-7 ->
        {:ok, %__MODULE__{h: h, s: 0.0, l: 100.0, alpha: alpha}}

      l < 1.0e-8 ->
        {:ok, %__MODULE__{h: h, s: 0.0, l: 0.0, alpha: alpha}}

      true ->
        mx = Color.HSLuv.Gamut.max_safe_chroma_for_l(l)
        s = c / mx * 100
        {:ok, %__MODULE__{h: h, s: s, l: l, alpha: alpha}}
    end
  end

  @doc """
  Converts an HPLuv color to CIE `XYZ` via `LCHuv`.

  """
  def to_xyz(%__MODULE__{} = hpluv) do
    with {:ok, lch} <- to_lchuv(hpluv), do: Color.LCHuv.to_xyz(lch)
  end

  @doc """
  Converts a CIE `XYZ` color to HPLuv via `LCHuv`.

  """
  def from_xyz(%Color.XYZ{} = xyz) do
    with {:ok, lch} <- Color.LCHuv.from_xyz(xyz), do: from_lchuv(lch)
  end
end
