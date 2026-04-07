defmodule Color.Conversion.Oklab do
  @moduledoc """
  Pure math for the Oklab perceptual color space, published by
  Björn Ottosson in 2020 (https://bottosson.github.io/posts/oklab/).

  Oklab is defined relative to CIE XYZ under the D65 reference white
  with `Y` on the `[0, 1]` scale. If you have an `XYZ` tagged with a
  different illuminant, chromatically adapt it to D65 before using
  these functions — they do not adapt automatically.

  Note that Ottosson's published matrices use an implicit D65 of
  approximately `(0.9505, 1.0, 1.0883)` — the `Z` component differs
  from Lindbloom's published D65 (`1.08883`) by about `5 × 10⁻⁴`.
  This is intrinsic to the Oklab matrices and not a numerical bug.
  Round-tripping an `XYZ` through Oklab and back preserves the value
  to roughly `1 × 10⁻⁷`.

  The pipeline is:

      XYZ ──M1──▶ LMS ──∛──▶ LMS' ──M2──▶ Oklab

  with `M1` the D65 Hunt-Pointer-Estevez-like matrix and `M2` the final
  linear projection. The functions here are the inverse of each other
  to double precision.

  """

  # XYZ (D65) -> LMS
  @m1 [
    [0.8189330101, 0.3618667424, -0.1288597137],
    [0.0329845436, 0.9293118715, 0.0361456387],
    [0.0482003018, 0.2643662691, 0.6338517070]
  ]

  # LMS -> XYZ (D65)
  @m1_inv [
    [1.2270138511, -0.5577999807, 0.2812561490],
    [-0.0405801784, 1.1122568696, -0.0716766787],
    [-0.0763812845, -0.4214819784, 1.5861632204]
  ]

  # LMS' -> Oklab
  @m2 [
    [0.2104542553, 0.7936177850, -0.0040720468],
    [1.9779984951, -2.4285922050, 0.4505937099],
    [0.0259040371, 0.7827717662, -0.8086757660]
  ]

  # Oklab -> LMS'
  @m2_inv [
    [1.0, 0.3963377774, 0.2158037573],
    [1.0, -0.1055613458, -0.0638541728],
    [1.0, -0.0894841775, -1.2914855480]
  ]

  alias Color.Conversion.Lindbloom

  @doc """
  Converts a CIE `XYZ` triple (D65, `Y ∈ [0, 1]`) to an Oklab `{L, a, b}`.

  ### Arguments

  * `xyz` is an `{X, Y, Z}` tuple relative to the D65 reference white.

  ### Returns

  * An `{l, a, b}` tuple where `L` is perceptual lightness (0 for black,
    1 for the reference white) and `a`/`b` are green-red / blue-yellow
    opponent axes.

  ### Examples

      iex> {l, a, b} = Color.Conversion.Oklab.xyz_to_oklab({0.95047, 1.0, 1.08883})
      iex> {Float.round(l, 3), abs(a) < 1.0e-4, abs(b) < 1.0e-4}
      {1.0, true, true}

  """
  def xyz_to_oklab({_x, _y, _z} = xyz) do
    lms = Lindbloom.rgb_to_xyz(xyz, @m1)
    lms_p = cbrt_triple(lms)
    Lindbloom.rgb_to_xyz(lms_p, @m2)
  end

  @doc """
  Converts an Oklab `{L, a, b}` triple to CIE `XYZ` (D65, `Y ∈ [0, 1]`).

  ### Arguments

  * `oklab` is an `{L, a, b}` tuple.

  ### Returns

  * An `{X, Y, Z}` tuple.

  ### Examples

      iex> {x, y, z} = Color.Conversion.Oklab.oklab_to_xyz({1.0, 0.0, 0.0})
      iex> {Float.round(x, 4), Float.round(y, 4), Float.round(z, 4)}
      {0.9505, 1.0, 1.0883}

  """
  def oklab_to_xyz({_l, _a, _b} = oklab) do
    lms_p = Lindbloom.rgb_to_xyz(oklab, @m2_inv)
    lms = cube_triple(lms_p)
    Lindbloom.rgb_to_xyz(lms, @m1_inv)
  end

  @doc """
  Converts Oklab `{L, a, b}` to cylindrical Oklch `{L, C, h}`.

  The hue `h` is returned in degrees in the range `[0, 360)`.

  ### Arguments

  * `oklab` is an `{L, a, b}` tuple.

  ### Returns

  * An `{L, C, h}` tuple.

  ### Examples

      iex> Color.Conversion.Oklab.oklab_to_oklch({0.5, 0.0, 0.0})
      {0.5, 0.0, 0.0}

  """
  def oklab_to_oklch({l, a, b}) do
    c = :math.sqrt(a * a + b * b)

    h =
      case :math.atan2(b, a) * 180 / :math.pi() do
        deg when deg < 0 -> deg + 360
        deg -> deg
      end

    {l, c, h}
  end

  @doc """
  Converts cylindrical Oklch `{L, C, h}` to Oklab `{L, a, b}`.

  ### Arguments

  * `oklch` is an `{L, C, h}` tuple where `h` is in degrees.

  ### Returns

  * An `{L, a, b}` tuple.

  ### Examples

      iex> Color.Conversion.Oklab.oklch_to_oklab({0.5, 0.0, 0.0})
      {0.5, 0.0, 0.0}

  """
  def oklch_to_oklab({l, c, h}) do
    rad = h * :math.pi() / 180
    {l, c * :math.cos(rad), c * :math.sin(rad)}
  end

  defp cbrt_triple({a, b, c}), do: {cbrt(a), cbrt(b), cbrt(c)}
  defp cube_triple({a, b, c}), do: {a * a * a, b * b * b, c * c * c}

  defp cbrt(x) when x >= 0, do: :math.pow(x, 1 / 3)
  defp cbrt(x), do: -:math.pow(-x, 1 / 3)
end
