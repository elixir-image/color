defmodule Color.Lab do
  @moduledoc """
  CIE 1976 `L*a*b*` color space.

  Conversions between `L*a*b*` and `XYZ` use the formulas published by
  Bruce Lindbloom (http://www.brucelindbloom.com/index.html?Math.html)
  with the exact CIE constants `ε = 216/24389` and `κ = 24389/27`. The
  approximate 0.008856 / 7.787 forms found in many online references are
  not used.

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Lindbloom
  alias Color.Tristimulus

  defstruct [:l, :a, :b, :alpha, illuminant: :D65, observer_angle: 2]

  @type t :: %__MODULE__{
          l: number() | nil,
          a: number() | nil,
          b: number() | nil,
          alpha: number() | nil,
          illuminant: atom(),
          observer_angle: 2 | 10
        }

  @doc """
  Converts an `L*a*b*` color to a CIE `XYZ` color.

  ### Arguments

  * `lab` is a `Color.Lab` struct.

  * `options` is a keyword list.

  ### Options

  * `:illuminant` overrides the reference-white illuminant from the
    `lab` struct. Defaults to `lab.illuminant`.

  * `:observer_angle` overrides the observer angle (`2` or `10`).
    Defaults to `lab.observer_angle`.

  ### Returns

  * A `Color.XYZ` struct whose `Y` is on the same scale as the reference
    white (typically `Y ∈ [0, 1]`).

  ### Examples

      iex> {:ok, xyz} = Color.Lab.to_xyz(%Color.Lab{l: 100.0, a: 0.0, b: 0.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0888}

  """
  def to_xyz(%__MODULE__{l: l, a: a, b: b, alpha: alpha} = lab, options \\ []) do
    illuminant = Keyword.get(options, :illuminant, lab.illuminant)
    observer_angle = Keyword.get(options, :observer_angle, lab.observer_angle)

    {x, y, z} =
      Lindbloom.lab_to_xyz(
        {l, a, b},
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
  Converts a CIE `XYZ` color to an `L*a*b*` color.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct. Its `:illuminant` and `:observer_angle`
    fields select the reference white.

  ### Returns

  * A `Color.Lab` struct tagged with the same illuminant and observer
    angle as the input `xyz`.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, lab} = Color.Lab.from_xyz(xyz)
      iex> {Float.round(lab.l, 3), Float.round(lab.a, 3), Float.round(lab.b, 3)}
      {100.0, 0.0, 0.0}

  """
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha} = xyz) do
    illuminant = xyz.illuminant || :D65
    observer_angle = xyz.observer_angle || 2

    {l, a, b} =
      Lindbloom.xyz_to_lab(
        {x, y, z},
        Tristimulus.reference_white_tuple(
          illuminant: illuminant,
          observer_angle: observer_angle
        )
      )

    {:ok,
     %__MODULE__{
       l: l,
       a: a,
       b: b,
       alpha: alpha,
       illuminant: illuminant,
       observer_angle: observer_angle
     }}
  end
end
