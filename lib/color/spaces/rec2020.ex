defmodule Color.Rec2020 do
  @moduledoc """
  ITU-R BT.2020 / Rec. 2020 color space, using the Rec. 2020 wide-gamut
  primaries (D65 reference white) and the BT.2020 SDR opto-electronic
  transfer function at 12-bit precision.

  Rec. 2020 is the wide-gamut color space standardised for UHDTV and is
  the basis for HDR signalling in BT.2100 (with PQ or HLG encoding). Its
  primaries enclose a substantially larger portion of the visible
  spectral locus than sRGB or P3.

  Channels `r`, `g` and `b` are unit floats in the nominal range `[0, 1]`.

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Lindbloom

  defstruct [:r, :g, :b, :alpha]

  @type t :: %__MODULE__{
          r: number() | nil,
          g: number() | nil,
          b: number() | nil,
          alpha: number() | nil
        }

  {:ok, info} = Color.RGB.WorkingSpace.rgb_conversion_matrix(:Rec2020)
  @to_xyz_matrix info.to_xyz
  @from_xyz_matrix info.from_xyz
  @illuminant info.illuminant
  @observer_angle info.observer_angle

  @doc """
  Converts a Rec. 2020 color to a CIE `XYZ` color.

  ### Arguments

  * `rec2020` is a `Color.Rec2020` struct with unit-range channels.

  ### Returns

  * A `Color.XYZ` struct tagged with D65/2°, `Y ∈ [0, 1]`.

  ### Examples

      iex> {:ok, xyz} = Color.Rec2020.to_xyz(%Color.Rec2020{r: 1.0, g: 1.0, b: 1.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0888}

  """
  @spec to_xyz(t()) :: {:ok, Color.XYZ.t()}
  def to_xyz(%__MODULE__{r: r, g: g, b: b, alpha: alpha}) do
    linear = {
      Lindbloom.rec2020_inverse_compand(r),
      Lindbloom.rec2020_inverse_compand(g),
      Lindbloom.rec2020_inverse_compand(b)
    }

    {x, y, z} = Lindbloom.rgb_to_xyz(linear, @to_xyz_matrix)

    {:ok,
     %Color.XYZ{
       x: x,
       y: y,
       z: z,
       alpha: alpha,
       illuminant: @illuminant,
       observer_angle: @observer_angle
     }}
  end

  @doc """
  Converts a CIE `XYZ` color (assumed D65/2°) to Rec. 2020.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.Rec2020` struct.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, rec} = Color.Rec2020.from_xyz(xyz)
      iex> {Float.round(rec.r, 3), Float.round(rec.g, 3), Float.round(rec.b, 3)}
      {1.0, 1.0, 1.0}

  """
  @spec from_xyz(Color.XYZ.t()) :: {:ok, t()}
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}) do
    {lr, lg, lb} = Lindbloom.xyz_to_rgb({x, y, z}, @from_xyz_matrix)

    {:ok,
     %__MODULE__{
       r: Lindbloom.rec2020_compand(lr),
       g: Lindbloom.rec2020_compand(lg),
       b: Lindbloom.rec2020_compand(lb),
       alpha: alpha
     }}
  end
end
