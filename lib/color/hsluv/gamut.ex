defmodule Color.HSLuv.Gamut do
  @moduledoc """
  Helpers that compute the sRGB gamut boundary inside CIELUV for
  HSLuv and HPLuv.

  These reimplement the reference algorithm from
  https://www.hsluv.org/implementations/ (Alexei Boronine) using the
  sRGB working-space XYZ→RGB matrix derived by
  `Color.RGB.WorkingSpace` from Lindbloom's primaries, so the result
  matches our `Color.SRGB` exactly.

  """

  @epsilon 216 / 24389
  @kappa 24389 / 27

  # Load the XYZ -> linear sRGB matrix at compile time.
  {:ok, info} = Color.RGB.WorkingSpace.rgb_conversion_matrix(:SRGB)
  @sm info.from_xyz

  @doc """
  Returns the six sRGB gamut boundary lines in CIELUV chroma space for
  a given `L`. Each line is `{slope, intercept}` describing
  `v = slope * u + intercept` in the chroma plane.

  ### Arguments

  * `l` is the CIELUV lightness.

  ### Returns

  * A list of six `{slope, intercept}` tuples.

  """
  def get_bounds(l) do
    sub1 = :math.pow(l + 16, 3) / 1_560_896

    sub2 =
      if sub1 > @epsilon do
        sub1
      else
        l / @kappa
      end

    [[m11, m12, m13], [m21, m22, m23], [m31, m32, m33]] = @sm

    for {m1, m2, m3} <- [{m11, m12, m13}, {m21, m22, m23}, {m31, m32, m33}],
        t <- [0, 1] do
      top1 = (284_517 * m1 - 94_839 * m3) * sub2
      top2 = (838_422 * m3 + 769_860 * m2 + 731_718 * m1) * l * sub2 - 769_860 * t * l
      bottom = (632_260 * m3 - 126_452 * m2) * sub2 + 126_452 * t
      {top1 / bottom, top2 / bottom}
    end
  end

  @doc """
  Returns the maximum chroma achievable inside the sRGB gamut for the
  given `(l, h)` in CIELUV coordinates, where `h` is in degrees.

  ### Arguments

  * `l` is the CIELUV lightness.

  * `h` is the hue in degrees.

  ### Returns

  * A non-negative float.

  """
  def max_chroma_for_lh(l, h) do
    hrad = h * :math.pi() / 180
    bounds = get_bounds(l)

    bounds
    |> Enum.map(&length_of_ray_until_intersect(hrad, &1))
    |> Enum.filter(&(&1 >= 0))
    |> Enum.min(fn -> :infinity end)
  end

  @doc """
  Returns the largest chroma for the given `l` such that HPLuv is still
  achromatic at any hue, i.e. the distance from the origin in `uv` to
  the *nearest* gamut boundary line.

  ### Arguments

  * `l` is the CIELUV lightness.

  ### Returns

  * A non-negative float.

  """
  def max_safe_chroma_for_l(l) do
    l
    |> get_bounds()
    |> Enum.map(fn {m1, b1} ->
      # perpendicular distance from origin to the line v = m1*u + b1
      abs(b1) / :math.sqrt(m1 * m1 + 1)
    end)
    |> Enum.min(fn -> :infinity end)
  end

  defp length_of_ray_until_intersect(theta, {m1, b1}) do
    b1 / (:math.sin(theta) - m1 * :math.cos(theta))
  end
end
