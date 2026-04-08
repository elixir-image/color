defmodule Color.LCHab do
  @moduledoc """
  Cylindrical representation of CIE `L*a*b*`: lightness, chroma, hue.

  The `h` hue is expressed in degrees in `[0, 360)`.

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Lindbloom

  defstruct [:l, :c, :h, :alpha, illuminant: :D65, observer_angle: 2]

  @type t :: %__MODULE__{
          l: number() | nil,
          c: number() | nil,
          h: number() | nil,
          alpha: number() | nil,
          illuminant: atom(),
          observer_angle: 2 | 10
        }

  @doc """
  Converts an `LCHab` color to `L*a*b*`.

  ### Arguments

  * `lch` is a `Color.LCHab` struct.

  ### Returns

  * A `Color.Lab` struct.

  ### Examples

      iex> {:ok, lab} = Color.LCHab.to_lab(%Color.LCHab{l: 50.0, c: 0.0, h: 0.0})
      iex> {lab.l, lab.a, lab.b}
      {50.0, 0.0, 0.0}

  """
  def to_lab(%__MODULE__{l: l, c: c, h: h, alpha: alpha} = lch) do
    {l2, a, b} = Lindbloom.lchab_to_lab({l, c, h})

    {:ok,
     %Color.Lab{
       l: l2,
       a: a,
       b: b,
       alpha: alpha,
       illuminant: lch.illuminant,
       observer_angle: lch.observer_angle
     }}
  end

  @doc """
  Converts an `L*a*b*` color to `LCHab`.

  ### Arguments

  * `lab` is a `Color.Lab` struct.

  ### Returns

  * A `Color.LCHab` struct.

  ### Examples

      iex> lab = %Color.Lab{l: 50.0, a: 0.0, b: 0.0}
      iex> {:ok, lch} = Color.LCHab.from_lab(lab)
      iex> {lch.l, lch.c, lch.h}
      {50.0, 0.0, 0.0}

  """
  def from_lab(%Color.Lab{l: l, a: a, b: b, alpha: alpha} = lab) do
    {l2, c, h} = Lindbloom.lab_to_lchab({l, a, b})

    {:ok,
     %__MODULE__{
       l: l2,
       c: c,
       h: h,
       alpha: alpha,
       illuminant: lab.illuminant,
       observer_angle: lab.observer_angle
     }}
  end

  @doc """
  Converts an `LCHab` color to CIE `XYZ` via `L*a*b*`.

  ### Arguments

  * `lch` is a `Color.LCHab` struct.

  ### Returns

  * A `Color.XYZ` struct.

  ### Examples

      iex> {:ok, xyz} = Color.LCHab.to_xyz(%Color.LCHab{l: 100.0, c: 0.0, h: 0.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0888}

  """
  def to_xyz(%__MODULE__{} = lch) do
    with {:ok, lab} <- to_lab(lch) do
      Color.Lab.to_xyz(lab)
    end
  end

  @doc """
  Converts a CIE `XYZ` color to `LCHab` via `L*a*b*`.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.LCHab` struct.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, lch} = Color.LCHab.from_xyz(xyz)
      iex> {Float.round(lch.l, 2), Float.round(lch.c, 5)}
      {100.0, 0.0}

  """
  def from_xyz(%Color.XYZ{} = xyz) do
    with {:ok, lab} <- Color.Lab.from_xyz(xyz) do
      from_lab(lab)
    end
  end
end
