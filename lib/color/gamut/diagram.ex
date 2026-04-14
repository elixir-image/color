defmodule Color.Gamut.Diagram do
  @moduledoc """
  Geometric primitives for drawing **chromaticity diagrams** —
  the "horseshoe" plots used to visualise gamuts side-by-side.

  This module is pure data. It does no rendering; it returns
  lists of points and maps of triangles that any renderer (SVG,
  PNG, a 3D engine) can consume. The companion renderer that
  ships with the library is the Gamut tab of
  `Color.Palette.Visualizer`, which emits inline SVG.

  ## Projections

  Two chromaticity projections are supported:

  * `:xy` — CIE 1931 `(x, y)`. The historical default, the plot
    everyone recognises. Badly perceptually skewed — the green
    region dominates visually, the blue corner is crushed.

  * `:uv` — CIE 1976 `(u', v')`. Modern default. Same underlying
    chromaticity data, a more perceptually uniform projection:
    `u' = 4x / (−2x + 12y + 3)`, `v' = 9y / (−2x + 12y + 3)`.

  ## Primitives

  * `spectral_locus/2` — the horseshoe itself, as a list of
    points tracing monochromatic light from 380 nm (violet) to
    700 nm (red).

  * `triangle/2` — one working space's primaries and white
    point, as a four-entry map.

  * `planckian_locus/2` — the curve of blackbody chromaticities
    from 1000 K to 25000 K, with CCT annotations.

  * `chromaticity/2` — projects any `Color.input()` to a single
    point in the chosen plane.

  * `xy_to_uv/1` / `uv_to_xy/1` — the projection conversions,
    exposed in case callers have raw chromaticities already.

  """

  @type projection :: :xy | :uv

  @type xy_point :: %{x: float(), y: float()}
  @type uv_point :: %{u: float(), v: float()}
  @type point :: xy_point() | uv_point()

  @type spectral_point ::
          %{
            wavelength: number(),
            x: float(),
            y: float()
          }
          | %{
              wavelength: number(),
              u: float(),
              v: float()
            }

  @type triangle :: %{
          red: point(),
          green: point(),
          blue: point(),
          white: point()
        }

  @doc """
  Returns the visible-spectrum locus — the outer curve of the
  chromaticity diagram — as a list of points.

  The list traces monochromatic light from the shortest to the
  longest wavelength in the CIE 1931 2° observer's CMF table.
  To close the diagram visually, callers typically add a line
  segment from the last point back to the first (the "line of
  purples") when rendering.

  ### Arguments

  * `projection` is `:xy` (default) or `:uv`.

  ### Options

  * `:observer` is `2` (default) or `10` — CIE 1931 2° or CIE
    1964 10° standard observer.

  * `:step` is the wavelength step in nm to subsample the CMF
    table by. Default `5` nm (every point). Use a larger value
    (e.g. `10`) for faster rendering at small sizes.

  ### Returns

  * A list of maps with `:wavelength` plus the projection's
    coordinate keys (`:x, :y` or `:u, :v`).

  ### Examples

      iex> points = Color.Gamut.Diagram.spectral_locus(:xy)
      iex> first = hd(points)
      iex> first.wavelength
      380.0
      iex> Float.round(first.x, 4)
      0.1741

      iex> points = Color.Gamut.Diagram.spectral_locus(:uv)
      iex> point = Enum.find(points, &(&1.wavelength == 520.0))
      iex> Float.round(point.u, 4)
      0.0231

  """
  @spec spectral_locus(projection(), keyword()) :: [spectral_point()]
  def spectral_locus(projection \\ :xy, options \\ []) do
    observer = Keyword.get(options, :observer, 2)
    step = Keyword.get(options, :step, 5)

    {x_s, y_s, z_s} = Color.Spectral.cmf(observer)
    wavelengths = x_s.wavelengths

    [wavelengths, x_s.values, y_s.values, z_s.values]
    |> Enum.zip()
    |> Enum.reject(fn {wavelength, _, _, _} ->
      # Wavelengths > 700 nm are nearly zero and don't contribute
      # a useful locus point — they crowd on top of the 700 nm
      # point and make the line of purples ugly.
      wavelength > 700.0
    end)
    |> Enum.filter(fn {wavelength, _, _, _} ->
      int_wl = trunc(wavelength)
      rem(int_wl, step) == 0 or wavelength == 380.0
    end)
    |> Enum.map(fn {wavelength, x_bar, y_bar, z_bar} ->
      project_point(wavelength, x_bar, y_bar, z_bar, projection)
    end)
  end

  @doc """
  Returns the primaries and white point of a named RGB working
  space as chromaticities in the requested projection.

  ### Arguments

  * `working_space` is a working-space atom (for example
    `:SRGB`, `:P3_D65`, `:AdobeRGB` / `:Adobe`, `:Rec2020`,
    `:ProPhoto`).

  * `projection` is `:xy` (default) or `:uv`.

  ### Returns

  * A map with `:red`, `:green`, `:blue`, `:white` keys, each a
    `%{x, y}` or `%{u, v}` point.

  ### Examples

      iex> t = Color.Gamut.Diagram.triangle(:SRGB)
      iex> {Float.round(t.red.x, 2), Float.round(t.red.y, 2)}
      {0.64, 0.33}

      iex> t = Color.Gamut.Diagram.triangle(:P3_D65)
      iex> {Float.round(t.green.x, 3), Float.round(t.green.y, 3)}
      {0.265, 0.69}

  """
  @spec triangle(atom(), projection()) :: triangle()
  def triangle(working_space, projection \\ :xy) when is_atom(working_space) do
    p = Color.RGB.WorkingSpace.primaries(working_space)
    {xr, yr} = p.red
    {xg, yg} = p.green
    {xb, yb} = p.blue
    {xw, yw} = illuminant_xy(p.illuminant)

    %{
      red: project_xy(xr, yr, projection),
      green: project_xy(xg, yg, projection),
      blue: project_xy(xb, yb, projection),
      white: project_xy(xw, yw, projection)
    }
  end

  @doc """
  Returns points along the **Planckian (blackbody) locus** from
  `min` to `max` Kelvin at the given step.

  ### Arguments

  * `range` is a `Range.t()` of Kelvin values, e.g.
    `1000..20000//500`.

  * `projection` is `:xy` (default) or `:uv`.

  ### Returns

  * A list of maps with `:kelvin` plus the projection's
    coordinate keys.

  ### Examples

      iex> points = Color.Gamut.Diagram.planckian_locus(2000..10000//1000)
      iex> length(points)
      9
      iex> d65ish = Enum.find(points, &(&1.kelvin == 6000))
      iex> Float.round(d65ish.x, 3)
      0.322

  """
  @spec planckian_locus(Range.t(), projection()) :: [map()]
  def planckian_locus(range, projection \\ :xy) do
    Enum.map(range, fn kelvin ->
      {x, y} = Color.Temperature.xy(kelvin)
      Map.put(project_xy(x, y, projection), :kelvin, kelvin)
    end)
  end

  @doc """
  Returns the chromaticity of any colour input in the requested
  projection.

  ### Arguments

  * `color` is anything accepted by `Color.new/1`.

  * `projection` is `:xy` (default) or `:uv`.

  ### Returns

  * `{:ok, %{x, y}}` or `{:ok, %{u, v}}` on success.

  * `{:error, exception}` if the colour can't be parsed or
    converted.

  ### Examples

      iex> {:ok, point} = Color.Gamut.Diagram.chromaticity("#ff0000")
      iex> {Float.round(point.x, 3), Float.round(point.y, 3)}
      {0.64, 0.33}

      iex> {:ok, point} = Color.Gamut.Diagram.chromaticity("white")
      iex> {Float.round(point.x, 4), Float.round(point.y, 4)}
      {0.3127, 0.329}

  """
  @spec chromaticity(Color.input(), projection()) ::
          {:ok, point()} | {:error, Exception.t()}
  def chromaticity(color, projection \\ :xy) do
    with {:ok, xyy} <- Color.convert(color, Color.XyY) do
      {:ok, project_xy(xyy.x, xyy.y, projection)}
    end
  end

  @doc """
  Converts a CIE 1931 `(x, y)` chromaticity to CIE 1976
  `(u', v')`.

  ### Arguments

  * `{x, y}` is a chromaticity tuple.

  ### Returns

  * `{u, v}` — the u'v' coordinates.

  ### Examples

      iex> {u, v} = Color.Gamut.Diagram.xy_to_uv({0.3127, 0.3290})
      iex> {Float.round(u, 4), Float.round(v, 4)}
      {0.1978, 0.4683}

  """
  @spec xy_to_uv({number(), number()}) :: {float(), float()}
  def xy_to_uv({x, y}) do
    denom = -2.0 * x + 12.0 * y + 3.0

    if denom == 0.0 do
      {0.0, 0.0}
    else
      {4.0 * x / denom, 9.0 * y / denom}
    end
  end

  @doc """
  Converts a CIE 1976 `(u', v')` chromaticity back to CIE 1931
  `(x, y)`.

  ### Arguments

  * `{u, v}` is a u'v' chromaticity tuple.

  ### Returns

  * `{x, y}` — the xy coordinates.

  ### Examples

      iex> {x, y} = Color.Gamut.Diagram.uv_to_xy({0.1978, 0.4683})
      iex> {Float.round(x, 3), Float.round(y, 3)}
      {0.313, 0.329}

  """
  @spec uv_to_xy({number(), number()}) :: {float(), float()}
  def uv_to_xy({u, v}) do
    denom = 6.0 * u - 16.0 * v + 12.0

    if denom == 0.0 do
      {0.0, 0.0}
    else
      {9.0 * u / denom, 4.0 * v / denom}
    end
  end

  # ---- helpers -----------------------------------------------------------

  defp project_point(wavelength, x_bar, y_bar, z_bar, projection) do
    sum = x_bar + y_bar + z_bar

    {x, y} =
      if sum == 0.0 do
        {0.0, 0.0}
      else
        {x_bar / sum, y_bar / sum}
      end

    Map.put(project_xy(x, y, projection), :wavelength, wavelength)
  end

  defp project_xy(x, y, :xy), do: %{x: x * 1.0, y: y * 1.0}

  defp project_xy(x, y, :uv) do
    {u, v} = xy_to_uv({x, y})
    %{u: u, v: v}
  end

  # Look up an illuminant's (x, y) chromaticity from its D65-normalised
  # XYZ tuple in Color.Tristimulus.
  defp illuminant_xy(illuminant) do
    {xx, yy, zz} = Color.Tristimulus.reference_white_tuple(illuminant: illuminant)
    sum = xx + yy + zz

    if sum == 0.0, do: {0.0, 0.0}, else: {xx / sum, yy / sum}
  end
end
