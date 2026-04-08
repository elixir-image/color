defmodule Color.AdobeRGB do
  @moduledoc """
  Adobe RGB (1998) color space, using the Lindbloom Adobe working space
  (primaries from Adobe RGB (1998) specification, D65 reference white)
  and simple gamma companding with `γ = 2.19921875`.

  Channels `r`, `g`, `b` are unit floats in `[0, 1]`.

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

  @gamma 2.19921875

  {:ok, info} = Color.RGB.WorkingSpace.rgb_conversion_matrix(:Adobe)
  @to_xyz_matrix info.to_xyz
  @from_xyz_matrix info.from_xyz
  @illuminant info.illuminant
  @observer_angle info.observer_angle

  @doc """
  Converts an Adobe RGB color to a CIE `XYZ` color.

  ### Arguments

  * `adobe` is a `Color.AdobeRGB` struct with unit-range channels.

  ### Returns

  * A `Color.XYZ` struct tagged with D65/2°, `Y ∈ [0, 1]`.

  ### Examples

      iex> {:ok, xyz} = Color.AdobeRGB.to_xyz(%Color.AdobeRGB{r: 1.0, g: 1.0, b: 1.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0888}

  """
  def to_xyz(%__MODULE__{r: r, g: g, b: b, alpha: alpha}) do
    linear = {
      Lindbloom.gamma_inverse_compand(r, @gamma),
      Lindbloom.gamma_inverse_compand(g, @gamma),
      Lindbloom.gamma_inverse_compand(b, @gamma)
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
  Converts a CIE `XYZ` color (assumed D65/2°) to Adobe RGB.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.AdobeRGB` struct.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, adobe} = Color.AdobeRGB.from_xyz(xyz)
      iex> {Float.round(adobe.r, 3), Float.round(adobe.g, 3), Float.round(adobe.b, 3)}
      {1.0, 1.0, 1.0}

  """
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}) do
    {lr, lg, lb} = Lindbloom.xyz_to_rgb({x, y, z}, @from_xyz_matrix)

    {:ok,
     %__MODULE__{
       r: Lindbloom.gamma_compand(lr, @gamma),
       g: Lindbloom.gamma_compand(lg, @gamma),
       b: Lindbloom.gamma_compand(lb, @gamma),
       alpha: alpha
     }}
  end
end
