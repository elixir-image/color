defmodule Color.Spectral do
  @moduledoc """
  Spectral power distributions, spectral reflectances, and spectrum →
  XYZ integration.

  A `Color.Spectral` struct holds a list of wavelengths (in nm) and a
  matching list of values. For **emissive** sources the values are
  absolute or relative spectral power. For **reflective** samples the
  values are the per-wavelength reflectance in `[0.0, 1.0]`.

  The module provides:

  * `illuminant/1` — well-known CIE illuminants (`:D65`, `:D50`, `:A`,
    `:E`) as ready-to-use SPDs.

  * `cmf/1` — the CIE 1931 2° (default) and CIE 1964 10° standard
    observer colour matching functions.

  * `to_xyz/1,2` — integrates an SPD against a CMF to produce a
    `Color.XYZ` struct. The `Y` component is normalised to `1.0` for
    the chosen illuminant's reference white (so this matches the rest
    of the library's convention).

  * `reflectance_to_xyz/3` — multiplies a reflectance SPD by an
    illuminant SPD, then integrates. This is what you use for paint
    samples, fabric, printed swatches, etc.

  * `metamerism/4` — compares two spectral samples under two
    illuminants to detect metamers: pairs that match under one light
    and diverge under another.

  The standard tables are at 5 nm intervals from 380 nm to 780 nm
  (81 samples). All the built-in data lives in
  `Color.Spectral.Tables`. If you load a sample with a different
  wavelength grid, `to_xyz/2` will linearly interpolate it onto the
  5 nm grid before integrating.

  """

  alias Color.Spectral.Tables

  defstruct [:wavelengths, :values]

  @type t :: %__MODULE__{
          wavelengths: [number()],
          values: [number()]
        }

  @doc """
  Returns a `Color.Spectral` struct for a named CIE illuminant.

  ### Arguments

  * `name` is one of `:D65`, `:D50`, `:A`, `:E`.

  ### Returns

  * A `Color.Spectral` struct with 81 samples at 5 nm from 380 to
    780 nm.

  ### Examples

      iex> spd = Color.Spectral.illuminant(:D65)
      iex> length(spd.wavelengths)
      81

      iex> spd = Color.Spectral.illuminant(:E)
      iex> Enum.uniq(spd.values)
      [100.0]

  """
  def illuminant(name) when name in [:D65, :D50, :A, :E] do
    %__MODULE__{
      wavelengths: Tables.wavelengths(),
      values: Map.fetch!(Tables.illuminants(), name)
    }
  end

  @doc """
  Returns the CIE standard observer colour matching functions as three
  `Color.Spectral` structs (`{x_bar, y_bar, z_bar}`).

  ### Arguments

  * `observer_angle` is `2` (CIE 1931) or `10` (CIE 1964). Defaults
    to `2`.

  ### Returns

  * A `{x_bar, y_bar, z_bar}` tuple of `Color.Spectral` structs.

  ### Examples

      iex> {x, y, z} = Color.Spectral.cmf()
      iex> {length(x.values), length(y.values), length(z.values)}
      {81, 81, 81}

  """
  def cmf(observer_angle \\ 2)

  def cmf(2), do: unpack_cmf(Tables.cmf_1931())
  def cmf(10), do: unpack_cmf(Tables.cmf_1964())

  defp unpack_cmf(rows) do
    wavelengths = Tables.wavelengths()

    {x_vals, y_vals, z_vals} =
      Enum.reduce(rows, {[], [], []}, fn {x, y, z}, {xs, ys, zs} ->
        {[x | xs], [y | ys], [z | zs]}
      end)

    {
      %__MODULE__{wavelengths: wavelengths, values: Enum.reverse(x_vals)},
      %__MODULE__{wavelengths: wavelengths, values: Enum.reverse(y_vals)},
      %__MODULE__{wavelengths: wavelengths, values: Enum.reverse(z_vals)}
    }
  end

  @doc """
  Converts a spectral power distribution to a CIE `XYZ` tristimulus.

  This is the general formula used for emissive sources (monitors,
  LEDs, light bulbs):

      X = k · Σ S(λ) · x̄(λ)
      Y = k · Σ S(λ) · ȳ(λ)
      Z = k · Σ S(λ) · z̄(λ)

  where the normalising constant `k = 1 / Σ S(λ) · ȳ(λ)` so `Y = 1.0`
  at the source's own white point.

  ### Arguments

  * `spd` is a `Color.Spectral` struct representing the source's
    spectral power distribution.

  * `options` is a keyword list.

  ### Options

  * `:observer` is `2` or `10`. Defaults to `2`.

  * `:illuminant` tags the resulting `Color.XYZ` struct. Defaults to
    `:D65`. This does **not** normalise the result against that
    illuminant — use `reflectance_to_xyz/3` for that case.

  ### Returns

  * `{:ok, %Color.XYZ{}}`.

  ### Examples

      iex> d65 = Color.Spectral.illuminant(:D65)
      iex> {:ok, xyz} = Color.Spectral.to_xyz(d65)
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9504, 1.0, 1.0888}

      iex> a = Color.Spectral.illuminant(:A)
      iex> {:ok, xyz} = Color.Spectral.to_xyz(a, illuminant: :A)
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {1.0985, 1.0, 0.3558}

  """
  def to_xyz(%__MODULE__{} = spd, options \\ []) do
    observer = Keyword.get(options, :observer, 2)
    illuminant = Keyword.get(options, :illuminant, :D65)

    {x_bar, y_bar, z_bar} = cmf(observer)
    grid = Tables.wavelengths()
    values = resample(spd, grid)

    x_vals = x_bar.values
    y_vals = y_bar.values
    z_vals = z_bar.values

    {sum_x, sum_y, sum_z} =
      Enum.zip([values, x_vals, y_vals, z_vals])
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {v, x, y, z}, {sx, sy, sz} ->
        {sx + v * x, sy + v * y, sz + v * z}
      end)

    # Normalise so Y = 1.0 at the source's own output (i.e. the
    # chromaticity comes out correctly and the luminance matches our
    # Y = 1.0 reference-white convention).
    k = 1.0 / sum_y

    {:ok,
     %Color.XYZ{
       x: k * sum_x,
       y: 1.0,
       z: k * sum_z,
       illuminant: illuminant,
       observer_angle: observer
     }}
  end

  @doc """
  Converts a spectral **reflectance** sample under a specific
  illuminant to a CIE `XYZ` tristimulus.

  This is the formula used for paint chips, fabric swatches, printed
  samples, and anything else that reflects rather than emits light:

      X = k · Σ R(λ) · I(λ) · x̄(λ)
      Y = k · Σ R(λ) · I(λ) · ȳ(λ)
      Z = k · Σ R(λ) · I(λ) · z̄(λ)

  where the normalising constant `k = 1 / Σ I(λ) · ȳ(λ)` so `Y = 1.0`
  for a perfect (100% reflective) diffuser under the same illuminant.

  ### Arguments

  * `reflectance` is a `Color.Spectral` struct whose values are in
    `[0.0, 1.0]`.

  * `illuminant_name` is `:D65`, `:D50`, `:A`, or `:E`. Defaults to
    `:D65`.

  * `options` is a keyword list. Supports `:observer` (`2` or `10`,
    default `2`).

  ### Returns

  * `{:ok, %Color.XYZ{}}` tagged with the chosen illuminant.

  ### Examples

      iex> perfect_diffuser = %Color.Spectral{
      ...>   wavelengths: Color.Spectral.Tables.wavelengths(),
      ...>   values: List.duplicate(1.0, 81)
      ...> }
      iex> {:ok, xyz} = Color.Spectral.reflectance_to_xyz(perfect_diffuser, :D65)
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9504, 1.0, 1.0888}

      iex> {:ok, xyz} = Color.Spectral.reflectance_to_xyz(%Color.Spectral{
      ...>   wavelengths: Color.Spectral.Tables.wavelengths(),
      ...>   values: List.duplicate(1.0, 81)
      ...> }, :D50)
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9642, 1.0, 0.8251}

  """
  def reflectance_to_xyz(%__MODULE__{} = reflectance, illuminant_name \\ :D65, options \\ []) do
    observer = Keyword.get(options, :observer, 2)

    illuminant_spd = Map.fetch!(Tables.illuminants(), illuminant_name)
    {x_bar, y_bar, z_bar} = cmf(observer)
    grid = Tables.wavelengths()
    r_vals = resample(reflectance, grid)

    x_vals = x_bar.values
    y_vals = y_bar.values
    z_vals = z_bar.values

    {sum_x, sum_y, sum_z, sum_n} =
      Enum.zip([r_vals, illuminant_spd, x_vals, y_vals, z_vals])
      |> Enum.reduce({0.0, 0.0, 0.0, 0.0}, fn {r, i, x, y, z}, {sx, sy, sz, sn} ->
        product = r * i
        {sx + product * x, sy + product * y, sz + product * z, sn + i * y}
      end)

    k = 1.0 / sum_n

    {:ok,
     %Color.XYZ{
       x: k * sum_x,
       y: k * sum_y,
       z: k * sum_z,
       illuminant: illuminant_name,
       observer_angle: observer
     }}
  end

  @doc """
  Computes a metamerism index between two spectral reflectance
  samples under two different illuminants.

  Two samples that match under illuminant `a` (same XYZ or very
  close) may diverge visibly under illuminant `b`. The returned
  value is the CIEDE2000 ΔE between their appearances under the
  second illuminant — larger is "more metameric".

  ### Arguments

  * `sample_a` is a `Color.Spectral` reflectance.

  * `sample_b` is a `Color.Spectral` reflectance.

  * `reference` is the illuminant under which the samples match
    (for example `:D65`).

  * `test` is the illuminant under which to measure divergence (for
    example `:A` — tungsten light — is the classic test illuminant).

  ### Returns

  * `{:ok, delta_e}` with `delta_e` as a non-negative float (CIEDE2000).

  ### Examples

      iex> a = %Color.Spectral{
      ...>   wavelengths: Color.Spectral.Tables.wavelengths(),
      ...>   values: List.duplicate(0.5, 81)
      ...> }
      iex> {:ok, de} = Color.Spectral.metamerism(a, a, :D65, :A)
      iex> de
      0.0

  """
  def metamerism(
        %__MODULE__{} = sample_a,
        %__MODULE__{} = sample_b,
        reference,
        test
      ) do
    with {:ok, _ref_a} <- reflectance_to_xyz(sample_a, reference),
         {:ok, _ref_b} <- reflectance_to_xyz(sample_b, reference),
         {:ok, test_a} <- reflectance_to_xyz(sample_a, test),
         {:ok, test_b} <- reflectance_to_xyz(sample_b, test) do
      {:ok, Color.Distance.delta_e_2000(test_a, test_b)}
    end
  end

  # ---- resampling ----------------------------------------------------------

  @doc """
  Resamples a spectral struct onto a new wavelength grid via linear
  interpolation. Samples outside the source range are extrapolated
  as zero.

  ### Arguments

  * `spd` is a `Color.Spectral` struct.

  * `grid` is a list of wavelengths in nm.

  ### Returns

  * A list of values corresponding to each grid point.

  """
  def resample(%__MODULE__{wavelengths: ws, values: vs} = spd, grid) do
    if ws == grid do
      vs
    else
      pairs = Enum.zip(ws, vs)
      Enum.map(grid, fn lambda -> interpolate(pairs, lambda) end)
    end
    |> tap(fn _ -> spd end)
  end

  defp interpolate([], _lambda), do: 0.0
  defp interpolate([{w, v}], lambda) when w == lambda, do: v
  defp interpolate([{_w, _v}], _lambda), do: 0.0

  defp interpolate([{w1, v1}, {w2, v2} | rest], lambda) do
    cond do
      lambda < w1 ->
        0.0

      lambda <= w2 ->
        if w2 == w1 do
          v1
        else
          t = (lambda - w1) / (w2 - w1)
          v1 + t * (v2 - v1)
        end

      true ->
        interpolate([{w2, v2} | rest], lambda)
    end
  end
end
