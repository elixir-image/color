defmodule Color.Oklab do
  @moduledoc """
  Oklab perceptual color space (Björn Ottosson, 2020).

  Oklab is defined relative to CIE XYZ under the D65 reference white
  with `Y ∈ [0, 1]`. Conversions here assume the input `Color.XYZ` is
  already D65; if it is tagged with a different illuminant you should
  chromatically adapt it first with `Color.ChromaticAdaptation`.

  """

  alias Color.Conversion.Oklab, as: Math

  defstruct [:l, :a, :b, :alpha]

  @doc """
  Converts an Oklab color to a CIE `XYZ` color (D65/2°).

  ### Arguments

  * `oklab` is a `Color.Oklab` struct.

  ### Returns

  * A `Color.XYZ` struct tagged D65/2°.

  ### Examples

      iex> {:ok, xyz} = Color.Oklab.to_xyz(%Color.Oklab{l: 1.0, a: 0.0, b: 0.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0883}

  """
  def to_xyz(%__MODULE__{l: l, a: a, b: b, alpha: alpha}) do
    {x, y, z} = Math.oklab_to_xyz({l, a, b})

    {:ok,
     %Color.XYZ{
       x: x,
       y: y,
       z: z,
       alpha: alpha,
       illuminant: :D65,
       observer_angle: 2
     }}
  end

  @doc """
  Converts a CIE `XYZ` color (D65/2°) to Oklab.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct. Its illuminant should be `:D65`;
    if not, adapt first with `Color.ChromaticAdaptation`.

  ### Returns

  * A `Color.Oklab` struct.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, oklab} = Color.Oklab.from_xyz(xyz)
      iex> {Float.round(oklab.l, 3), abs(oklab.a) < 1.0e-4, abs(oklab.b) < 1.0e-4}
      {1.0, true, true}

  """
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}) do
    {l, a, b} = Math.xyz_to_oklab({x, y, z})
    {:ok, %__MODULE__{l: l, a: a, b: b, alpha: alpha}}
  end
end
