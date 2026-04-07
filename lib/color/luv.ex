defmodule Color.Luv do
  @moduledoc """
  CIE 1976 `L*u*v*` color space.

  Conversions use the Lindbloom formulas with exact CIE constants
  `ε = 216/24389` and `κ = 24389/27`.

  """

  alias Color.Conversion.Lindbloom
  alias Color.Tristimulus

  defstruct [:l, :u, :v, :alpha, illuminant: :D65, observer_angle: 2]

  @doc """
  Converts an `L*u*v*` color to a CIE `XYZ` color.

  ### Arguments

  * `luv` is a `Color.Luv` struct.

  * `options` is a keyword list.

  ### Options

  * `:illuminant` overrides the reference-white illuminant from the
    `luv` struct. Defaults to `luv.illuminant`.

  * `:observer_angle` overrides the observer angle. Defaults to
    `luv.observer_angle`.

  ### Returns

  * A `Color.XYZ` struct.

  ### Examples

      iex> {:ok, xyz} = Color.Luv.to_xyz(%Color.Luv{l: 100.0, u: 0.0, v: 0.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0888}

  """
  def to_xyz(%__MODULE__{l: l, u: u, v: v, alpha: alpha} = luv, options \\ []) do
    illuminant = Keyword.get(options, :illuminant, luv.illuminant)
    observer_angle = Keyword.get(options, :observer_angle, luv.observer_angle)

    {x, y, z} =
      Lindbloom.luv_to_xyz(
        {l, u, v},
        Tristimulus.reference_white_tuple(
          illuminant: illuminant,
          observer_angle: observer_angle
        )
      )

    {:ok,
     %Color.XYZ{
       x: x,
       y: y,
       z: z,
       alpha: alpha,
       illuminant: illuminant,
       observer_angle: observer_angle
     }}
  end

  @doc """
  Converts a CIE `XYZ` color to an `L*u*v*` color.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.Luv` struct tagged with the same illuminant and observer
    angle as the input `xyz`.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, luv} = Color.Luv.from_xyz(xyz)
      iex> {Float.round(luv.l, 3), Float.round(luv.u, 3), Float.round(luv.v, 3)}
      {100.0, 0.0, 0.0}

  """
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha} = xyz) do
    illuminant = xyz.illuminant || :D65
    observer_angle = xyz.observer_angle || 2

    {l, u, v} =
      Lindbloom.xyz_to_luv(
        {x, y, z},
        Tristimulus.reference_white_tuple(
          illuminant: illuminant,
          observer_angle: observer_angle
        )
      )

    {:ok,
     %__MODULE__{
       l: l,
       u: u,
       v: v,
       alpha: alpha,
       illuminant: illuminant,
       observer_angle: observer_angle
     }}
  end
end
