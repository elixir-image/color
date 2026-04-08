defmodule Color.CMYK do
  @moduledoc """
  Device CMYK color space. This is the simple "subtractive from sRGB"
  device CMYK — it does NOT use an ICC profile, so it is not suitable
  for color-accurate print workflows. For that, pass the sRGB (or
  AdobeRGB) struct through a real CMS.

  All channels are unit floats in `[0, 1]`.

  """

  @behaviour Color.Behaviour

  defstruct [:c, :m, :y, :k, :alpha]

  @typedoc """
  A simple subtractive CMYK colour. Each of `c`, `m`, `y`, `k` is a
  unit float in `[0.0, 1.0]`. No ICC profile is implied — this is
  device-independent CMYK suitable for `device-cmyk()` interchange,
  not for press output.
  """
  @type t :: %__MODULE__{
          c: float() | nil,
          m: float() | nil,
          y: float() | nil,
          k: float() | nil,
          alpha: Color.Types.alpha()
        }

  @doc """
  Converts a CMYK color to sRGB.

  ### Arguments

  * `cmyk` is a `Color.CMYK` struct.

  ### Returns

  * A `Color.SRGB` struct.

  ### Examples

      iex> {:ok, srgb} = Color.CMYK.to_srgb(%Color.CMYK{c: 0.0, m: 0.0, y: 0.0, k: 0.0})
      iex> {srgb.r, srgb.g, srgb.b}
      {1.0, 1.0, 1.0}

      iex> {:ok, srgb} = Color.CMYK.to_srgb(%Color.CMYK{c: 1.0, m: 1.0, y: 0.0, k: 0.0})
      iex> {srgb.r, srgb.g, srgb.b}
      {0.0, 0.0, 1.0}

  """
  def to_srgb(%__MODULE__{c: c, m: m, y: y, k: k, alpha: alpha}) do
    r = (1 - c) * (1 - k)
    g = (1 - m) * (1 - k)
    b = (1 - y) * (1 - k)
    {:ok, %Color.SRGB{r: r, g: g, b: b, alpha: alpha}}
  end

  @doc """
  Converts an sRGB color to CMYK.

  ### Arguments

  * `srgb` is a `Color.SRGB` struct.

  ### Returns

  * A `Color.CMYK` struct.

  ### Examples

      iex> {:ok, cmyk} = Color.CMYK.from_srgb(%Color.SRGB{r: 0.0, g: 0.0, b: 1.0})
      iex> {cmyk.c, cmyk.m, cmyk.y, cmyk.k}
      {1.0, 1.0, 0.0, 0.0}

  """
  def from_srgb(%Color.SRGB{r: r, g: g, b: b, alpha: alpha}) do
    k = 1 - max(max(r, g), b)

    {c, m, y} =
      if k == 1.0 do
        {0.0, 0.0, 0.0}
      else
        {(1 - r - k) / (1 - k), (1 - g - k) / (1 - k), (1 - b - k) / (1 - k)}
      end

    {:ok, %__MODULE__{c: c, m: m, y: y, k: k, alpha: alpha}}
  end

  @doc """
  Converts a CMYK color to CIE `XYZ` via sRGB.

  """
  def to_xyz(%__MODULE__{} = cmyk) do
    with {:ok, srgb} <- to_srgb(cmyk), do: Color.SRGB.to_xyz(srgb)
  end

  @doc """
  Converts a CIE `XYZ` color to CMYK via sRGB.

  """
  def from_xyz(%Color.XYZ{} = xyz) do
    with {:ok, srgb} <- Color.SRGB.from_xyz(xyz), do: from_srgb(srgb)
  end
end
