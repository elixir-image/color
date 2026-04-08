defmodule Color.Oklch do
  @moduledoc """
  Cylindrical representation of Oklab: lightness, chroma, hue.

  Hue `h` is expressed in degrees in `[0, 360)`.

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Oklab, as: Math

  defstruct [:l, :c, :h, :alpha]

  @typedoc """
  Cylindrical Oklab. `l` is lightness in `[0.0, 1.0]`, `c` is chroma
  `≥ 0`, and `h` is hue in degrees `[0.0, 360.0)`. Defined against D65.
  """
  @type t :: %__MODULE__{
          l: float() | nil,
          c: float() | nil,
          h: float() | nil,
          alpha: Color.Types.alpha()
        }

  @doc """
  Converts an Oklch color to Oklab.

  ### Arguments

  * `oklch` is a `Color.Oklch` struct.

  ### Returns

  * A `Color.Oklab` struct.

  ### Examples

      iex> {:ok, oklab} = Color.Oklch.to_oklab(%Color.Oklch{l: 0.5, c: 0.0, h: 0.0})
      iex> {oklab.l, oklab.a, oklab.b}
      {0.5, 0.0, 0.0}

  """
  def to_oklab(%__MODULE__{l: l, c: c, h: h, alpha: alpha}) do
    {l2, a, b} = Math.oklch_to_oklab({l, c, h})
    {:ok, %Color.Oklab{l: l2, a: a, b: b, alpha: alpha}}
  end

  @doc """
  Converts an Oklab color to Oklch.

  ### Arguments

  * `oklab` is a `Color.Oklab` struct.

  ### Returns

  * A `Color.Oklch` struct.

  ### Examples

      iex> {:ok, oklch} = Color.Oklch.from_oklab(%Color.Oklab{l: 0.5, a: 0.0, b: 0.0})
      iex> {oklch.l, oklch.c, oklch.h}
      {0.5, 0.0, 0.0}

  """
  def from_oklab(%Color.Oklab{l: l, a: a, b: b, alpha: alpha}) do
    {l2, c, h} = Math.oklab_to_oklch({l, a, b})
    {:ok, %__MODULE__{l: l2, c: c, h: h, alpha: alpha}}
  end

  @doc """
  Converts an Oklch color to CIE `XYZ` (D65/2°) via Oklab.

  ### Arguments

  * `oklch` is a `Color.Oklch` struct.

  ### Returns

  * A `Color.XYZ` struct.

  ### Examples

      iex> {:ok, xyz} = Color.Oklch.to_xyz(%Color.Oklch{l: 1.0, c: 0.0, h: 0.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0883}

  """
  def to_xyz(%__MODULE__{} = oklch) do
    with {:ok, oklab} <- to_oklab(oklch), do: Color.Oklab.to_xyz(oklab)
  end

  @doc """
  Converts a CIE `XYZ` color (D65/2°) to Oklch via Oklab.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.Oklch` struct.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, oklch} = Color.Oklch.from_xyz(xyz)
      iex> {Float.round(oklch.l, 3), Float.round(oklch.c, 3)}
      {1.0, 0.0}

  """
  def from_xyz(%Color.XYZ{} = xyz) do
    with {:ok, oklab} <- Color.Oklab.from_xyz(xyz), do: from_oklab(oklab)
  end
end
