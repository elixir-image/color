defmodule Color.Hsv do
  @moduledoc """
  HSV color space — hue, saturation, value.

  All channels are unit floats in `[0, 1]`. HSV is a non-linear
  reparameterisation of sRGB, so conversions to any CIE space route
  through `Color.SRGB`.

  """

  defstruct [:h, :s, :v, :alpha]

  @doc """
  Converts an HSV color to sRGB.

  ### Arguments

  * `hsv` is a `Color.Hsv` struct.

  ### Returns

  * A `Color.SRGB` struct with unit-range channels.

  ### Examples

      iex> {:ok, srgb} = Color.Hsv.to_srgb(%Color.Hsv{h: 0.0, s: 1.0, v: 1.0})
      iex> {srgb.r, srgb.g, srgb.b}
      {1.0, 0.0, 0.0}

  """
  def to_srgb(%__MODULE__{h: _h, s: s, v: v, alpha: alpha}) when s == 0 do
    {:ok, %Color.SRGB{r: v, g: v, b: v, alpha: alpha}}
  end

  def to_srgb(%__MODULE__{h: h, s: s, v: v, alpha: alpha}) do
    var_h = h * 6
    var_h = if var_h == 6, do: 0, else: var_h

    var_i = floor(var_h)
    var_1 = v * (1 - s)
    var_2 = v * (1 - s * (var_h - var_i))
    var_3 = v * (1 - s * (1 - (var_h - var_i)))

    {r, g, b} =
      case var_i do
        0 -> {v, var_3, var_1}
        1 -> {var_2, v, var_1}
        2 -> {var_1, v, var_3}
        3 -> {var_1, var_2, v}
        4 -> {var_3, var_1, v}
        _other -> {v, var_1, var_2}
      end

    {:ok, %Color.SRGB{r: r, g: g, b: b, alpha: alpha}}
  end

  @doc """
  Converts an sRGB color to HSV.

  ### Arguments

  * `srgb` is a `Color.SRGB` struct with unit-range channels.

  ### Returns

  * A `Color.Hsv` struct.

  ### Examples

      iex> {:ok, hsv} = Color.Hsv.from_srgb(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0})
      iex> {hsv.h, hsv.s, hsv.v}
      {0.0, 1.0, 1.0}

  """
  def from_srgb(%Color.SRGB{r: r, g: g, b: b, alpha: alpha}) do
    max = max(max(r, g), b)
    min = min(min(r, g), b)
    delta = max - min

    v = max
    s = if max == 0, do: 0.0, else: delta / max

    h =
      cond do
        delta == 0 ->
          0.0

        max == r ->
          hue = (g - b) / delta / 6
          if hue < 0, do: hue + 1, else: hue

        max == g ->
          ((b - r) / delta + 2) / 6

        true ->
          ((r - g) / delta + 4) / 6
      end

    {:ok, %__MODULE__{h: h, s: s, v: v, alpha: alpha}}
  end

  @doc """
  Converts an HSV color to CIE `XYZ` via sRGB.

  """
  def to_xyz(%__MODULE__{} = hsv) do
    with {:ok, srgb} <- to_srgb(hsv), do: Color.SRGB.to_xyz(srgb)
  end

  @doc """
  Converts a CIE `XYZ` color to HSV via sRGB.

  """
  def from_xyz(%Color.XYZ{} = xyz) do
    with {:ok, srgb} <- Color.SRGB.from_xyz(xyz), do: from_srgb(srgb)
  end
end
