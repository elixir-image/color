defmodule Color.XYZ do
  @moduledoc """
  CIE 1931 XYZ tristimulus color space.

  The struct carries the `:illuminant` and `:observer_angle` of the
  reference white under which the `{x, y, z}` values are expressed.
  `Y` is typically on the `[0, 1]` scale, with `Y = 1.0` at the
  reference white.

  Chromatic adaptation between illuminants is provided by `adapt/3`,
  which applies one of the transforms from `Color.ChromaticAdaptation`.

  """

  alias Color.{ChromaticAdaptation, Conversion.Lindbloom}

  defstruct [:x, :y, :z, :alpha, :illuminant, :observer_angle]

  @doc """
  Identity conversion from `Color.XYZ` to `Color.XYZ`.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * `{:ok, xyz}`.

  """
  def from_xyz(%__MODULE__{} = xyz), do: {:ok, xyz}

  @doc """
  Identity conversion — returns the struct wrapped in an `:ok` tuple.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * `{:ok, xyz}`.

  """
  def to_xyz(%__MODULE__{} = xyz), do: {:ok, xyz}

  @doc """
  Chromatically adapts an `XYZ` color from its current reference white
  to a new reference white.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct. Its `:illuminant` and
    `:observer_angle` fields identify the source reference white.

  * `dest_illuminant` is the target illuminant atom (for example
    `:D65`).

  * `options` is a keyword list.

  ### Options

  * `:observer_angle` is the target observer angle (`2` or `10`).
    Defaults to `2`.

  * `:method` is the chromatic adaptation transform. One of
    `:bradford` (default), `:xyz_scaling`, `:von_kries`, `:sharp`,
    `:cmccat2000`, or `:cat02`.

  ### Returns

  * `{:ok, %Color.XYZ{}}` tagged with the new illuminant and observer
    angle.

  ### Examples

      iex> d50 = %Color.XYZ{x: 0.96422, y: 1.0, z: 0.82521, illuminant: :D50, observer_angle: 2}
      iex> {:ok, d65} = Color.XYZ.adapt(d50, :D65)
      iex> {Float.round(d65.x, 5), Float.round(d65.y, 5), Float.round(d65.z, 5)}
      {0.95047, 1.0, 1.08883}

  """
  def adapt(%__MODULE__{} = xyz, dest_illuminant, options \\ []) do
    source_illuminant = xyz.illuminant || :D65
    source_observer_angle = xyz.observer_angle || 2
    dest_observer_angle = Keyword.get(options, :observer_angle, 2)
    method = Keyword.get(options, :method, :bradford)

    if {source_illuminant, source_observer_angle} == {dest_illuminant, dest_observer_angle} do
      {:ok, xyz}
    else
      matrix =
        cached_matrix(
          source_illuminant,
          source_observer_angle,
          dest_illuminant,
          dest_observer_angle,
          method
        )

      {x, y, z} = Lindbloom.rgb_to_xyz({xyz.x, xyz.y, xyz.z}, matrix)

      {:ok,
       %__MODULE__{
         xyz
         | x: x,
           y: y,
           z: z,
           illuminant: dest_illuminant,
           observer_angle: dest_observer_angle
       }}
    end
  end

  @doc """
  Applies black point compensation (BPC) to an `XYZ` color.

  BPC rescales the XYZ such that the source's darkest reproducible
  black maps to the destination's darkest reproducible black, so
  that shadow detail is preserved across profiles with different
  minimum luminances. Without BPC, converting from a printer profile
  (whose darkest achievable black might be 3% of white) to a display
  profile (which can produce pure black) leaves shadows visibly
  lifted.

  The rescale is a linear map along the achromatic axis:

      Y_out = (Y_in - k_src) · (1 - k_dst) / (1 - k_src) + k_dst

  and `X` / `Z` are rescaled by the same factor so chromaticity is
  preserved.

  This library does not currently read ICC profiles, so in most
  workflows both black points default to `0.0` and `apply_bpc/3`
  becomes an identity. It is provided for explicit use in
  ICC-aware pipelines and for completeness of the rendering-intent
  API (see `Color.convert/3` with `bpc: true`).

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  * `source_bp` is the source black point as a relative luminance
    (`Y`) in `[0.0, 1.0]`.

  * `dest_bp` is the destination black point as a relative luminance.

  ### Returns

  * A new `Color.XYZ` struct with the compensation applied.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.5, y: 0.5, z: 0.5, illuminant: :D65}
      iex> Color.XYZ.apply_bpc(xyz, 0.0, 0.0) == xyz
      true

      iex> xyz = %Color.XYZ{x: 0.1, y: 0.1, z: 0.1, illuminant: :D65}
      iex> out = Color.XYZ.apply_bpc(xyz, 0.05, 0.0)
      iex> Float.round(out.y, 6)
      0.052632

  """
  def apply_bpc(%__MODULE__{} = xyz, source_bp, dest_bp)
      when is_number(source_bp) and is_number(dest_bp) do
    if source_bp == dest_bp do
      xyz
    else
      factor = (1 - dest_bp) / (1 - source_bp)

      %{
        xyz
        | x: (xyz.x - source_bp) * factor + dest_bp,
          y: (xyz.y - source_bp) * factor + dest_bp,
          z: (xyz.z - source_bp) * factor + dest_bp
      }
    end
  end

  defp cached_matrix(si, soa, di, doa, method) do
    key = {__MODULE__, :cat, si, soa, di, doa, method}

    case :persistent_term.get(key, :__uncached__) do
      :__uncached__ ->
        matrix =
          ChromaticAdaptation.adaptation_matrix_list(si, soa, di, doa, method)

        :persistent_term.put(key, matrix)
        matrix

      matrix ->
        matrix
    end
  end
end
