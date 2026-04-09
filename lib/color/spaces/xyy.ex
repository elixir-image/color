defmodule Color.XyY do
  @moduledoc """
  CIE xyY color space — chromaticity coordinates `x`, `y` and luminance `Y`.

  Conversions use the Lindbloom formulas. The `Y` channel carries the
  luminance on the same scale as CIE XYZ (typically `Y ∈ [0, 1]`).

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Lindbloom
  alias Color.Tristimulus

  defstruct x: nil,
            y: nil,
            yY: 1.0,
            alpha: nil,
            illuminant: :D65,
            observer_angle: 2

  @typedoc """
  CIE xyY chromaticity (`x`, `y`) plus luminance (`yY`). Useful for
  reasoning about gamut on a chromaticity diagram.
  """
  @type t :: %__MODULE__{
          x: float() | nil,
          y: float() | nil,
          yY: float() | nil,
          alpha: Color.Types.alpha(),
          illuminant: Color.Types.illuminant(),
          observer_angle: Color.Types.observer()
        }

  @doc """
  Converts an `xyY` color to CIE `XYZ`.

  ### Arguments

  * `xyy` is a `Color.XyY` struct.

  ### Returns

  * A `Color.XYZ` struct.

  ### Examples

      iex> {:ok, xyz} = Color.XyY.to_xyz(%Color.XyY{x: 0.31271, y: 0.32902, yY: 1.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9504, 1.0, 1.0889}

  """
  def to_xyz(%__MODULE__{x: x, y: y, yY: yy, alpha: alpha} = xyy) do
    {xi, yi, zi} = Lindbloom.xyy_to_xyz({x, y, yy})

    {:ok,
     %Color.XYZ{
       x: xi,
       y: yi,
       z: zi,
       alpha: alpha,
       illuminant: xyy.illuminant,
       observer_angle: xyy.observer_angle
     }}
  end

  # Legacy list-based helpers used at compile time by Color.Tristimulus.
  # These do NOT participate in the to_xyz/1 callback shape — the
  # struct clause above is the one and only canonical implementation.

  @doc false
  def to_xyz_list(["_", "_"]), do: nil
  def to_xyz_list([x, y]), do: to_xyz_list([x, y, 1.0])

  def to_xyz_list([x, y, yY]) do
    xi = x * yY / y
    yi = yY
    zi = (1.0 - x - y) * yY / y
    [xi, yi, zi]
  end

  @doc """
  Converts a CIE `XYZ` color to `xyY`.

  When `X + Y + Z = 0` the chromaticity is taken from the `xyz`'s
  reference white, as prescribed by Lindbloom.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.XyY` struct.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, xyy} = Color.XyY.from_xyz(xyz)
      iex> {Float.round(xyy.x, 5), Float.round(xyy.y, 5), Float.round(xyy.yY, 4)}
      {0.31273, 0.32902, 1.0}

  """
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha} = xyz) do
    illuminant = xyz.illuminant || :D65
    observer_angle = xyz.observer_angle || 2
    wr = Tristimulus.reference_white_tuple(illuminant: illuminant, observer_angle: observer_angle)

    {xc, yc, yy} = Lindbloom.xyz_to_xyy({x, y, z}, wr)

    {:ok,
     %__MODULE__{
       x: xc,
       y: yc,
       yY: yy,
       alpha: alpha,
       illuminant: illuminant,
       observer_angle: observer_angle
     }}
  end
end
