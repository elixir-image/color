defmodule Color.Hsl do
  @moduledoc """
  HSL color space — hue, saturation, lightness.

  All channels are unit floats in `[0, 1]`. HSL is a non-linear
  reparameterisation of sRGB, so conversions to any CIE space route
  through `Color.SRGB`.

  """

  defstruct [:h, :s, :l, :alpha]

  @doc """
  Converts an HSL color to sRGB.

  ### Arguments

  * `hsl` is a `Color.Hsl` struct.

  ### Returns

  * A `Color.SRGB` struct with unit-range channels.

  ### Examples

      iex> {:ok, srgb} = Color.Hsl.to_srgb(%Color.Hsl{h: 0.0, s: 1.0, l: 0.5})
      iex> {srgb.r, srgb.g, srgb.b}
      {1.0, 0.0, 0.0}

  """
  def to_srgb(%__MODULE__{h: _h, s: s, l: l, alpha: alpha}) when s == 0 do
    {:ok, %Color.SRGB{r: l, g: l, b: l, alpha: alpha}}
  end

  def to_srgb(%__MODULE__{h: h, s: s, l: l, alpha: alpha}) do
    var_2 = if l < 0.5, do: l * (1 + s), else: l + s - s * l
    var_1 = 2 * l - var_2

    r = hue_to_rgb(var_1, var_2, h + 1 / 3)
    g = hue_to_rgb(var_1, var_2, h)
    b = hue_to_rgb(var_1, var_2, h - 1 / 3)

    {:ok, %Color.SRGB{r: r, g: g, b: b, alpha: alpha}}
  end

  @doc """
  Converts an sRGB color to HSL.

  ### Arguments

  * `srgb` is a `Color.SRGB` struct with unit-range channels.

  ### Returns

  * A `Color.Hsl` struct.

  ### Examples

      iex> {:ok, hsl} = Color.Hsl.from_srgb(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0})
      iex> {hsl.h, hsl.s, hsl.l}
      {0.0, 1.0, 0.5}

  """
  def from_srgb(%Color.SRGB{r: r, g: g, b: b, alpha: alpha}) do
    max = max(max(r, g), b)
    min = min(min(r, g), b)
    delta = max - min
    l = (max + min) / 2

    {h, s} =
      if delta == 0 do
        {0.0, 0.0}
      else
        s = if l < 0.5, do: delta / (max + min), else: delta / (2 - max - min)
        h = hue(max, r, g, b, delta)
        {h, s}
      end

    {:ok, %__MODULE__{h: h, s: s, l: l, alpha: alpha}}
  end

  @doc """
  Converts an HSL color to CIE `XYZ` via sRGB.

  ### Arguments

  * `hsl` is a `Color.Hsl` struct.

  ### Returns

  * A `Color.XYZ` struct.

  """
  def to_xyz(%__MODULE__{} = hsl) do
    with {:ok, srgb} <- to_srgb(hsl), do: Color.SRGB.to_xyz(srgb)
  end

  @doc """
  Converts a CIE `XYZ` color to HSL via sRGB.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.Hsl` struct.

  """
  def from_xyz(%Color.XYZ{} = xyz) do
    with {:ok, srgb} <- Color.SRGB.from_xyz(xyz), do: from_srgb(srgb)
  end

  defp hue(max, r, g, b, delta) do
    h =
      cond do
        max == r -> (g - b) / delta + if(g < b, do: 6, else: 0)
        max == g -> (b - r) / delta + 2
        true -> (r - g) / delta + 4
      end

    h / 6
  end

  defp hue_to_rgb(v1, v2, vh) do
    vh =
      cond do
        vh < 0 -> vh + 1
        vh > 1 -> vh - 1
        true -> vh
      end

    cond do
      6 * vh < 1 -> v1 + (v2 - v1) * 6 * vh
      2 * vh < 1 -> v2
      3 * vh < 2 -> v1 + (v2 - v1) * (2 / 3 - vh) * 6
      true -> v1
    end
  end
end
