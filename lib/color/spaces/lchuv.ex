defmodule Color.LCHuv do
  @moduledoc """
  Cylindrical representation of CIE `L*u*v*`: lightness, chroma, hue.

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
  Converts an `LCHuv` color to `L*u*v*`.

  ### Arguments

  * `lch` is a `Color.LCHuv` struct.

  ### Returns

  * A `Color.Luv` struct.

  ### Examples

      iex> {:ok, luv} = Color.LCHuv.to_luv(%Color.LCHuv{l: 50.0, c: 0.0, h: 0.0})
      iex> {luv.l, luv.u, luv.v}
      {50.0, 0.0, 0.0}

  """
  def to_luv(%__MODULE__{l: l, c: c, h: h, alpha: alpha} = lch) do
    {l2, u, v} = Lindbloom.lchuv_to_luv({l, c, h})

    {:ok,
     %Color.Luv{
       l: l2,
       u: u,
       v: v,
       alpha: alpha,
       illuminant: lch.illuminant,
       observer_angle: lch.observer_angle
     }}
  end

  @doc """
  Converts an `L*u*v*` color to `LCHuv`.

  ### Arguments

  * `luv` is a `Color.Luv` struct.

  ### Returns

  * A `Color.LCHuv` struct.

  ### Examples

      iex> luv = %Color.Luv{l: 50.0, u: 0.0, v: 0.0}
      iex> {:ok, lch} = Color.LCHuv.from_luv(luv)
      iex> {lch.l, lch.c, lch.h}
      {50.0, 0.0, 0.0}

  """
  def from_luv(%Color.Luv{l: l, u: u, v: v, alpha: alpha} = luv) do
    {l2, c, h} = Lindbloom.luv_to_lchuv({l, u, v})

    {:ok,
     %__MODULE__{
       l: l2,
       c: c,
       h: h,
       alpha: alpha,
       illuminant: luv.illuminant,
       observer_angle: luv.observer_angle
     }}
  end

  @doc """
  Converts an `LCHuv` color to CIE `XYZ` via `L*u*v*`.

  ### Arguments

  * `lch` is a `Color.LCHuv` struct.

  ### Returns

  * A `Color.XYZ` struct.

  """
  def to_xyz(%__MODULE__{} = lch) do
    with {:ok, luv} <- to_luv(lch) do
      Color.Luv.to_xyz(luv)
    end
  end

  @doc """
  Converts a CIE `XYZ` color to `LCHuv` via `L*u*v*`.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.LCHuv` struct.

  """
  def from_xyz(%Color.XYZ{} = xyz) do
    with {:ok, luv} <- Color.Luv.from_xyz(xyz) do
      from_luv(luv)
    end
  end
end
