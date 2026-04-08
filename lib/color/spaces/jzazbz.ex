defmodule Color.JzAzBz do
  @moduledoc """
  JzAzBz perceptually-uniform color space for HDR and wide-gamut
  content, from Safdar, Cui, Kim & Luo (2017), "Perceptually uniform
  color space for image signals including high dynamic range and wide
  gamut".

  JzAzBz is designed on top of CIE XYZ under D65 expressed in
  **absolute luminance (cd/m²)**. Our `Color.XYZ` is on the `Y = 1.0`
  scale, so we multiply by a reference peak luminance before the
  JzAzBz transform and divide on the way back.

  The default reference luminance is 100 cd/m², which matches the
  traditional SDR reference white and produces Jz values consistent
  with the JzAzBz paper's examples. For HDR workflows, pass
  `:reference_luminance` (in cd/m², up to 10,000) as an option.

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Lindbloom

  defstruct [:jz, :az, :bz, :alpha]

  @typedoc """
  A JzAzBz colour (Safdar et al. 2017), an HDR/wide-gamut perceptual
  space. `jz` is lightness, `az` and `bz` are chromatic axes.
  """
  @type t :: %__MODULE__{
          jz: float() | nil,
          az: float() | nil,
          bz: float() | nil,
          alpha: Color.Types.alpha()
        }

  # Safdar et al. 2017 constants
  @b 1.15
  @g 0.66
  @c1 3424 / 4096
  @c2 2413 / 128
  @c3 2392 / 128
  @n 2610 / 16384
  @p 1.7 * 2523 / 32
  @d -0.56
  @d0 1.6295499532821566e-11

  @m1 [
    [0.41478972, 0.579999, 0.0146480],
    [-0.2015100, 1.120649, 0.0531008],
    [-0.0166008, 0.264800, 0.6684799]
  ]

  @m2 [
    [0.5, 0.5, 0.0],
    [3.524000, -4.066708, 0.542708],
    [0.199076, 1.096799, -1.295875]
  ]

  @m1_inv Lindbloom.invert3(@m1)
  @m2_inv Lindbloom.invert3(@m2)

  @doc """
  Converts CIE `XYZ` (D65, `Y ∈ [0, 1]`) to JzAzBz.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.JzAzBz` struct.

  ### Examples

      iex> {:ok, jz} = Color.JzAzBz.from_xyz(%Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2})
      iex> {Float.round(jz.jz, 4), abs(jz.az) < 1.0e-3, abs(jz.bz) < 1.0e-3}
      {0.1672, true, true}

  """
  def from_xyz(xyz, options \\ [])

  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}, options) do
    ref = Keyword.get(options, :reference_luminance, 100)

    x = x * ref
    y = y * ref
    z = z * ref

    xp = @b * x - (@b - 1) * z
    yp = @g * y - (@g - 1) * x
    zp = z

    lms = Lindbloom.rgb_to_xyz({xp, yp, zp}, @m1)
    lms_p = pq_triple(lms)
    {iz, az, bz} = Lindbloom.rgb_to_xyz(lms_p, @m2)

    jz = (1 + @d) * iz / (1 + @d * iz) - @d0

    {:ok, %__MODULE__{jz: jz, az: az, bz: bz, alpha: alpha}}
  end

  @doc """
  Converts JzAzBz to CIE `XYZ` (D65, `Y ∈ [0, 1]`).

  ### Arguments

  * `jzazbz` is a `Color.JzAzBz` struct.

  ### Returns

  * A `Color.XYZ` struct tagged D65/2°.

  """
  def to_xyz(jzazbz, options \\ [])

  def to_xyz(%__MODULE__{jz: jz, az: az, bz: bz, alpha: alpha}, options) do
    ref = Keyword.get(options, :reference_luminance, 100)

    iz = (jz + @d0) / (1 + @d - @d * (jz + @d0))

    lms_p = Lindbloom.rgb_to_xyz({iz, az, bz}, @m2_inv)
    lms = pq_inv_triple(lms_p)
    {xp, yp, zp} = Lindbloom.rgb_to_xyz(lms, @m1_inv)

    x = (xp + (@b - 1) * zp) / @b
    y = (yp + (@g - 1) * x) / @g
    z = zp

    {:ok,
     %Color.XYZ{
       x: x / ref,
       y: y / ref,
       z: z / ref,
       alpha: alpha,
       illuminant: :D65,
       observer_angle: 2
     }}
  end

  defp pq_triple({a, b, c}), do: {pq(a), pq(b), pq(c)}
  defp pq_inv_triple({a, b, c}), do: {pq_inv(a), pq_inv(b), pq_inv(c)}

  defp pq(v) when v <= 0, do: 0.0

  defp pq(v) do
    vn = :math.pow(v / 10_000, @n)
    :math.pow((@c1 + @c2 * vn) / (1 + @c3 * vn), @p)
  end

  defp pq_inv(v) when v <= 0, do: 0.0

  defp pq_inv(v) do
    vp = :math.pow(v, 1 / @p)
    num = max(vp - @c1, 0)
    den = @c2 - @c3 * vp
    10_000 * :math.pow(num / den, 1 / @n)
  end
end
