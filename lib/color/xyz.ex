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
