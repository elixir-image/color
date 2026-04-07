defmodule Color.Temperature do
  @moduledoc """
  Correlated colour temperature (CCT) on the Planckian locus.

  * `cct/1` — McCamy's 1992 approximation: given any colour (or an
    `{x, y}` chromaticity pair), returns the CCT in Kelvin.

  * `xy/1` — Kim et al. 2002 piecewise polynomial: given a CCT in
    Kelvin, returns the `{x, y}` chromaticity of the corresponding
    blackbody radiator (accurate to ~`1e-3` over 1667–25000 K).

  * `xyz/1,2` — same as `xy/1` but returns a `Color.XYZ` struct
    tagged D65/2° by default, with an optional luminance.

  """

  @doc """
  Returns the correlated colour temperature of a colour, in Kelvin,
  using McCamy's 1992 approximation.

  Accuracy is about ±2 K from 2856 K (illuminant A) to 6500 K (D65)
  and degrades smoothly outside that range. The McCamy formula is the
  classical one; for more accurate results use a Planckian-locus
  minimum-distance search (not provided here).

  ### Arguments

  * `color` is any colour accepted by `Color.new/1`, or an
    `{x, y}` chromaticity tuple of floats.

  ### Returns

  * A float — CCT in Kelvin.

  ### Examples

      iex> Float.round(Color.Temperature.cct({0.31271, 0.32902}), 0)
      6504.0

      iex> Float.round(Color.Temperature.cct({0.44757, 0.40745}), 0)
      2857.0

      iex> Float.round(Color.Temperature.cct("white"), 0)
      6503.0

  """
  def cct({x, y}) when is_number(x) and is_number(y) do
    n = (x - 0.3320) / (0.1858 - y)
    449 * :math.pow(n, 3) + 3525 * :math.pow(n, 2) + 6823.3 * n + 5520.33
  end

  def cct(color) do
    with {:ok, xyy} <- Color.convert(color, Color.XYY) do
      cct({xyy.x, xyy.y})
    end
  end

  @doc """
  Returns the `{x, y}` chromaticity for a colour temperature in
  Kelvin.

  For `T < 4000 K` (incandescent range), returns the chromaticity of
  the Planckian (blackbody) radiator at that temperature using the
  Kim et al. 2002 piecewise polynomial.

  For `T ≥ 4000 K` (daylight range), returns the chromaticity on the
  CIE daylight locus (CIE 15.2), which is what the standard daylight
  illuminants D50, D55, D65, D75 are built from. `xy(6500)` returns
  approximately D65's chromaticity; `xy(5000)` approximately D50's.

  Valid over `[1667, 25000]` K.

  ### Arguments

  * `kelvin` is a number in `[1667, 25000]`.

  ### Returns

  * An `{x, y}` tuple of floats.

  ### Examples

      iex> {x, y} = Color.Temperature.xy(6504)
      iex> {Float.round(x, 4), Float.round(y, 4)}
      {0.3127, 0.3291}

      iex> {x, y} = Color.Temperature.xy(2856)
      iex> {Float.round(x, 4), Float.round(y, 4)}
      {0.4471, 0.4075}

  """
  def xy(kelvin) when is_number(kelvin) do
    t = kelvin * 1.0
    if t < 4000, do: planckian(t), else: daylight(t)
  end

  @doc """
  Returns the `{x, y}` chromaticity on the Planckian (blackbody)
  locus at the given temperature, using the Kim et al. 2002
  polynomial. Valid over `[1667, 25000]` K.

  ### Arguments

  * `kelvin` is a number in `[1667, 25000]`.

  ### Returns

  * An `{x, y}` tuple.

  """
  def planckian(kelvin) when is_number(kelvin) do
    t = kelvin * 1.0

    x =
      if t < 4000 do
        -0.2661239e9 / :math.pow(t, 3) - 0.2343589e6 / :math.pow(t, 2) +
          0.8776956e3 / t + 0.179910
      else
        -3.0258469e9 / :math.pow(t, 3) + 2.1070379e6 / :math.pow(t, 2) +
          0.2226347e3 / t + 0.240390
      end

    y =
      cond do
        t < 2222 ->
          -1.1063814 * :math.pow(x, 3) - 1.34811020 * :math.pow(x, 2) +
            2.18555832 * x - 0.20219683

        t < 4000 ->
          -0.9549476 * :math.pow(x, 3) - 1.37418593 * :math.pow(x, 2) +
            2.09137015 * x - 0.16748867

        true ->
          3.0817580 * :math.pow(x, 3) - 5.87338670 * :math.pow(x, 2) +
            3.75112997 * x - 0.37001483
      end

    {x, y}
  end

  @doc """
  Returns the `{x, y}` chromaticity on the CIE daylight locus
  (CIE 15.2) at the given colour temperature. Valid over
  `[4000, 25000]` K.

  ### Arguments

  * `kelvin` is a number in `[4000, 25000]`.

  ### Returns

  * An `{x, y}` tuple.

  """
  def daylight(kelvin) when is_number(kelvin) do
    t = kelvin * 1.0

    x =
      if t <= 7000 do
        -4.6070e9 / :math.pow(t, 3) + 2.9678e6 / :math.pow(t, 2) +
          0.09911e3 / t + 0.244063
      else
        -2.0064e9 / :math.pow(t, 3) + 1.9018e6 / :math.pow(t, 2) +
          0.24748e3 / t + 0.237040
      end

    y = -3.000 * x * x + 2.870 * x - 0.275

    {x, y}
  end

  @doc """
  Returns a `Color.XYZ` struct at the given colour temperature, with
  `Y` scaled to the given luminance (default `1.0`).

  ### Arguments

  * `kelvin` is a number in `[1667, 25000]`.

  * `luminance` is the `Y` value to scale to. Defaults to `1.0`.

  ### Returns

  * A `Color.XYZ` struct tagged D65/2°.

  ### Examples

      iex> xyz = Color.Temperature.xyz(6504)
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9502, 1.0, 1.0883}

  """
  def xyz(kelvin, luminance \\ 1.0) do
    {x_chroma, y_chroma} = xy(kelvin)

    big_x = x_chroma * luminance / y_chroma
    big_y = luminance
    big_z = (1 - x_chroma - y_chroma) * luminance / y_chroma

    %Color.XYZ{x: big_x, y: big_y, z: big_z, illuminant: :D65, observer_angle: 2}
  end
end
