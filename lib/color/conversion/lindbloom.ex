defmodule Color.Conversion.Lindbloom do
  @moduledoc """
  Color space conversion functions based on the formulas published by
  Bruce Lindbloom at http://www.brucelindbloom.com/index.html?Math.html.

  All functions operate on plain tuples/lists of floats so they can be
  composed freely. Reference whites (`wr`) are supplied as `{xr, yr, zr}`
  tuples in the same scale as the `XYZ` values (typically `Y = 1.0` or
  `Y = 100.0`; both work as long as the inputs are consistent).

  The CIE constants `ε` and `κ` are used in their exact rational form as
  recommended by Lindbloom, rather than the rounded values found in many
  older references.

  ### Constants

  * `ε = 216/24389 ≈ 0.008856`.

  * `κ = 24389/27 ≈ 903.2963`.

  """

  # CIE standard (exact rational form, per Lindbloom)
  @epsilon 216 / 24389
  @kappa 24389 / 27

  @doc """
  Returns the CIE constants `ε` and `κ` used by the conversions.

  ### Returns

  * A `{epsilon, kappa}` tuple of floats.

  ### Examples

      iex> {e, k} = Color.Conversion.Lindbloom.constants()
      iex> Float.round(e, 6)
      0.008856
      iex> Float.round(k, 4)
      903.2963

  """
  def constants, do: {@epsilon, @kappa}

  # ---------------------------------------------------------------------------
  # XYZ <-> xyY
  # ---------------------------------------------------------------------------

  @doc """
  Converts a CIE `XYZ` triple to `xyY`.

  When `X + Y + Z = 0` the chromaticity is taken from the reference white
  as prescribed by Lindbloom.

  ### Arguments

  * `xyz` is an `{x, y, z}` tuple.

  * `wr` is the `{xr, yr, zr}` reference white used when `X + Y + Z = 0`.

  ### Returns

  * An `{x, y, y_big}` tuple where `x` and `y` are chromaticity coordinates
    and `y_big` is the original `Y`.

  ### Examples

      iex> Color.Conversion.Lindbloom.xyz_to_xyy({0.5, 0.5, 0.5}, {0.95047, 1.0, 1.08883})
      {0.3333333333333333, 0.3333333333333333, 0.5}

      iex> {x, y, yy} = Color.Conversion.Lindbloom.xyz_to_xyy({0.95047, 1.0, 1.08883}, {0.95047, 1.0, 1.08883})
      iex> {Float.round(x, 5), Float.round(y, 5), Float.round(yy, 4)}
      {0.31273, 0.32902, 1.0}

  """
  def xyz_to_xyy({x, y, z}, {xr, yr, zr}) do
    sum = x + y + z

    if sum == 0 do
      denom = xr + yr + zr
      {xr / denom, yr / denom, 0.0}
    else
      {x / sum, y / sum, y}
    end
  end

  @doc """
  Converts `xyY` chromaticity coordinates to a CIE `XYZ` triple.

  ### Arguments

  * `xyy` is an `{x, y, y_big}` tuple.

  ### Returns

  * An `{X, Y, Z}` tuple.

  ### Examples

      iex> {x, y, z} = Color.Conversion.Lindbloom.xyy_to_xyz({0.3127, 0.3290, 1.0})
      iex> {Float.round(x, 5), Float.round(y, 5), Float.round(z, 5)}
      {0.95046, 1.0, 1.08906}

  """
  def xyy_to_xyz({x, y, yy}) do
    if y == 0 do
      {0.0, 0.0, 0.0}
    else
      {x * yy / y, yy, (1.0 - x - y) * yy / y}
    end
  end

  # ---------------------------------------------------------------------------
  # XYZ <-> Lab
  # ---------------------------------------------------------------------------

  @doc """
  Converts a CIE `XYZ` triple to CIE `L*a*b*`.

  ### Arguments

  * `xyz` is an `{X, Y, Z}` tuple.

  * `wr` is the `{Xr, Yr, Zr}` reference white tuple.

  ### Returns

  * An `{l, a, b}` tuple.

  ### Examples

      iex> Color.Conversion.Lindbloom.xyz_to_lab({0.95047, 1.0, 1.08883}, {0.95047, 1.0, 1.08883})
      {100.0, 0.0, 0.0}

  """
  def xyz_to_lab({x, y, z}, {xr, yr, zr}) do
    fx = lab_f(x / xr)
    fy = lab_f(y / yr)
    fz = lab_f(z / zr)

    {116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)}
  end

  @doc """
  Converts CIE `L*a*b*` to a CIE `XYZ` triple.

  ### Arguments

  * `lab` is an `{l, a, b}` tuple.

  * `wr` is the `{Xr, Yr, Zr}` reference white tuple.

  ### Returns

  * An `{X, Y, Z}` tuple.

  ### Examples

      iex> {x, y, z} = Color.Conversion.Lindbloom.lab_to_xyz({100.0, 0.0, 0.0}, {0.95047, 1.0, 1.08883})
      iex> {Float.round(x, 5), Float.round(y, 5), Float.round(z, 5)}
      {0.95047, 1.0, 1.08883}

  """
  def lab_to_xyz({l, a, b}, {xr, yr, zr}) do
    fy = (l + 16) / 116
    fx = a / 500 + fy
    fz = fy - b / 200

    xr_rel = lab_f_inv(fx)

    yr_rel =
      if l > @kappa * @epsilon do
        fy * fy * fy
      else
        l / @kappa
      end

    zr_rel = lab_f_inv(fz)

    {xr_rel * xr, yr_rel * yr, zr_rel * zr}
  end

  defp lab_f(t) when t > @epsilon, do: :math.pow(t, 1 / 3)
  defp lab_f(t), do: (@kappa * t + 16) / 116

  defp lab_f_inv(f) do
    f3 = f * f * f

    if f3 > @epsilon do
      f3
    else
      (116 * f - 16) / @kappa
    end
  end

  # ---------------------------------------------------------------------------
  # XYZ <-> Luv
  # ---------------------------------------------------------------------------

  @doc """
  Converts a CIE `XYZ` triple to CIE `L*u*v*`.

  ### Arguments

  * `xyz` is an `{X, Y, Z}` tuple.

  * `wr` is the `{Xr, Yr, Zr}` reference white tuple.

  ### Returns

  * An `{l, u, v}` tuple.

  ### Examples

      iex> Color.Conversion.Lindbloom.xyz_to_luv({0.0, 0.0, 0.0}, {0.95047, 1.0, 1.08883})
      {0.0, 0.0, 0.0}

  """
  def xyz_to_luv({x, y, z}, {xr, yr, zr}) when x == 0 and y == 0 and z == 0 do
    _ = {xr, yr, zr}
    {0.0, 0.0, 0.0}
  end

  def xyz_to_luv({x, y, z}, {xr, yr, zr}) do
    {up, vp} = uv_prime(x, y, z)
    {urp, vrp} = uv_prime(xr, yr, zr)

    yrel = y / yr

    l =
      if yrel > @epsilon do
        116 * :math.pow(yrel, 1 / 3) - 16
      else
        @kappa * yrel
      end

    {l, 13 * l * (up - urp), 13 * l * (vp - vrp)}
  end

  @doc """
  Converts CIE `L*u*v*` to a CIE `XYZ` triple.

  ### Arguments

  * `luv` is an `{l, u, v}` tuple.

  * `wr` is the `{Xr, Yr, Zr}` reference white tuple.

  ### Returns

  * An `{X, Y, Z}` tuple.

  ### Examples

      iex> Color.Conversion.Lindbloom.luv_to_xyz({0.0, 0.0, 0.0}, {0.95047, 1.0, 1.08883})
      {0.0, 0.0, 0.0}

  """
  def luv_to_xyz({l, _u, _v}, _wr) when l == 0, do: {0.0, 0.0, 0.0}

  def luv_to_xyz({l, u, v}, {xr, yr, zr}) do
    y =
      if l > @kappa * @epsilon do
        fy = (l + 16) / 116
        fy * fy * fy * yr
      else
        l / @kappa * yr
      end

    {u0, v0} = uv_prime(xr, yr, zr)

    a = (52 * l / (u + 13 * l * u0) - 1) / 3
    b = -5 * y
    c = -1 / 3
    d = y * (39 * l / (v + 13 * l * v0) - 5)

    x = (d - b) / (a - c)
    z = x * a + b

    {x, y, z}
  end

  defp uv_prime(x, y, z) do
    denom = x + 15 * y + 3 * z

    if denom == 0 do
      {0.0, 0.0}
    else
      {4 * x / denom, 9 * y / denom}
    end
  end

  # ---------------------------------------------------------------------------
  # Lab <-> LCHab  and  Luv <-> LCHuv
  # ---------------------------------------------------------------------------

  @doc """
  Converts CIE `L*a*b*` to cylindrical `LCHab`.

  ### Arguments

  * `lab` is an `{l, a, b}` tuple.

  ### Returns

  * An `{l, c, h}` tuple where `h` is in degrees in the range `[0, 360)`.

  ### Examples

      iex> Color.Conversion.Lindbloom.lab_to_lchab({50.0, 0.0, 0.0})
      {50.0, 0.0, 0.0}

  """
  def lab_to_lchab({l, a, b}), do: {l, :math.sqrt(a * a + b * b), degrees_atan2(b, a)}

  @doc """
  Converts cylindrical `LCHab` to CIE `L*a*b*`.

  ### Arguments

  * `lch` is an `{l, c, h}` tuple with `h` in degrees.

  ### Returns

  * An `{l, a, b}` tuple.

  ### Examples

      iex> Color.Conversion.Lindbloom.lchab_to_lab({50.0, 0.0, 0.0})
      {50.0, 0.0, 0.0}

  """
  def lchab_to_lab({l, c, h}) do
    rad = h * :math.pi() / 180
    {l, c * :math.cos(rad), c * :math.sin(rad)}
  end

  @doc """
  Converts CIE `L*u*v*` to cylindrical `LCHuv`.

  ### Arguments

  * `luv` is an `{l, u, v}` tuple.

  ### Returns

  * An `{l, c, h}` tuple where `h` is in degrees in the range `[0, 360)`.

  ### Examples

      iex> Color.Conversion.Lindbloom.luv_to_lchuv({50.0, 0.0, 0.0})
      {50.0, 0.0, 0.0}

  """
  def luv_to_lchuv({l, u, v}), do: {l, :math.sqrt(u * u + v * v), degrees_atan2(v, u)}

  @doc """
  Converts cylindrical `LCHuv` to CIE `L*u*v*`.

  ### Arguments

  * `lch` is an `{l, c, h}` tuple with `h` in degrees.

  ### Returns

  * An `{l, u, v}` tuple.

  ### Examples

      iex> Color.Conversion.Lindbloom.lchuv_to_luv({50.0, 0.0, 0.0})
      {50.0, 0.0, 0.0}

  """
  def lchuv_to_luv({l, c, h}) do
    rad = h * :math.pi() / 180
    {l, c * :math.cos(rad), c * :math.sin(rad)}
  end

  defp degrees_atan2(y, x) do
    case :math.atan2(y, x) * 180 / :math.pi() do
      h when h < 0 -> h + 360
      h -> h
    end
  end

  # ---------------------------------------------------------------------------
  # RGB <-> XYZ  (linear RGB, given a 3x3 working-space matrix)
  # ---------------------------------------------------------------------------

  @doc """
  Converts linear `RGB` to `XYZ` using a working-space matrix `m`.

  Uses plain f64 arithmetic rather than `Nx`: for single-color 3x3 work
  the BEAM's float ops are roughly 25x faster than `Nx` on the host
  backend, and preserve double precision. `Nx` is still the right choice
  for batched color operations elsewhere in this project.

  ### Arguments

  * `rgb` is an `{r, g, b}` tuple of linear (companding-removed) values.

  * `m` is the 3x3 RGB→XYZ matrix for the working space, as a list of
    three three-element rows.

  ### Returns

  * An `{X, Y, Z}` tuple.

  ### Examples

      iex> m = [[0.4124564, 0.3575761, 0.1804375],
      ...>      [0.2126729, 0.7151522, 0.0721750],
      ...>      [0.0193339, 0.1191920, 0.9503041]]
      iex> {x, y, z} = Color.Conversion.Lindbloom.rgb_to_xyz({1.0, 1.0, 1.0}, m)
      iex> {Float.round(x, 4), Float.round(y, 4), Float.round(z, 4)}
      {0.9505, 1.0, 1.0888}

  """
  def rgb_to_xyz({r, g, b}, [[m11, m12, m13], [m21, m22, m23], [m31, m32, m33]]) do
    {
      m11 * r + m12 * g + m13 * b,
      m21 * r + m22 * g + m23 * b,
      m31 * r + m32 * g + m33 * b
    }
  end

  @doc """
  Converts `XYZ` to linear `RGB` using the inverse working-space matrix `mi`.

  ### Arguments

  * `xyz` is an `{X, Y, Z}` tuple.

  * `mi` is the 3x3 XYZ→RGB (inverse) matrix, as a list of three
    three-element rows.

  ### Returns

  * An `{r, g, b}` tuple of linear values.

  """
  def xyz_to_rgb({x, y, z}, [[m11, m12, m13], [m21, m22, m23], [m31, m32, m33]]) do
    {
      m11 * x + m12 * y + m13 * z,
      m21 * x + m22 * y + m23 * z,
      m31 * x + m32 * y + m33 * z
    }
  end

  @doc """
  Computes the 3x3 RGB→XYZ matrix for an RGB working space from its
  primary chromaticities and reference white, per Lindbloom.

  Given the primaries `{xr, yr}`, `{xg, yg}`, `{xb, yb}` and the reference
  white `{Xw, Yw, Zw}` the matrix is `[Sr·Xr Sg·Xg Sb·Xb; …]` where the
  scale factors `S` are found by solving `M · [Sr Sg Sb]ᵀ = W`.

  ### Arguments

  * `primaries` is a `{{xr, yr}, {xg, yg}, {xb, yb}}` tuple of chromaticities.

  * `wr` is the `{Xw, Yw, Zw}` reference white.

  ### Returns

  * The RGB→XYZ matrix as a list of three three-element rows.

  """
  def working_space_matrix({{xr_p, yr_p}, {xg_p, yg_p}, {xb_p, yb_p}}, {xw, yw, zw}) do
    xr = xr_p / yr_p
    zr = (1 - xr_p - yr_p) / yr_p

    xg = xg_p / yg_p
    zg = (1 - xg_p - yg_p) / yg_p

    xb = xb_p / yb_p
    zb = (1 - xb_p - yb_p) / yb_p

    # Solve [xr xg xb; 1 1 1; zr zg zb] * [Sr Sg Sb]ᵀ = [Xw Yw Zw]ᵀ
    {sr, sg, sb} =
      solve3(
        [[xr, xg, xb], [1.0, 1.0, 1.0], [zr, zg, zb]],
        {xw, yw, zw}
      )

    [
      [sr * xr, sg * xg, sb * xb],
      [sr, sg, sb],
      [sr * zr, sg * zg, sb * zb]
    ]
  end

  # Cramer's rule for a 3x3 system (Mx = v).
  defp solve3([[a, b, c], [d, e, f], [g, h, i]], {u, v, w}) do
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)

    x = (u * (e * i - f * h) - b * (v * i - f * w) + c * (v * h - e * w)) / det
    y = (a * (v * i - f * w) - u * (d * i - f * g) + c * (d * w - v * g)) / det
    z = (a * (e * w - v * h) - b * (d * w - v * g) + u * (d * h - e * g)) / det

    {x, y, z}
  end

  @doc """
  Multiplies two 3x3 matrices given as lists of rows.

  ### Arguments

  * `a` is a 3x3 matrix as a list of three three-element rows.

  * `b` is a 3x3 matrix in the same shape.

  ### Returns

  * The product `a · b` in the same shape.

  """
  def matmul3(
        [[a11, a12, a13], [a21, a22, a23], [a31, a32, a33]],
        [[b11, b12, b13], [b21, b22, b23], [b31, b32, b33]]
      ) do
    [
      [
        a11 * b11 + a12 * b21 + a13 * b31,
        a11 * b12 + a12 * b22 + a13 * b32,
        a11 * b13 + a12 * b23 + a13 * b33
      ],
      [
        a21 * b11 + a22 * b21 + a23 * b31,
        a21 * b12 + a22 * b22 + a23 * b32,
        a21 * b13 + a22 * b23 + a23 * b33
      ],
      [
        a31 * b11 + a32 * b21 + a33 * b31,
        a31 * b12 + a32 * b22 + a33 * b32,
        a31 * b13 + a32 * b23 + a33 * b33
      ]
    ]
  end

  @doc """
  Inverts a 3x3 matrix represented as a list of rows. Used to derive the
  XYZ→RGB matrix from the RGB→XYZ matrix.

  ### Arguments

  * `m` is a 3x3 matrix as a list of three three-element rows.

  ### Returns

  * The inverse matrix in the same shape.

  """
  def invert3([[a, b, c], [d, e, f], [g, h, i]]) do
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)

    [
      [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
      [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
      [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]
    ]
  end

  # ---------------------------------------------------------------------------
  # Companding (gamma / sRGB / L*)
  # ---------------------------------------------------------------------------

  @doc """
  Applies simple gamma companding (linear → non-linear).

  ### Arguments

  * `v` is a linear channel value.

  * `gamma` is the gamma exponent (for example `2.2`).

  """
  def gamma_compand(v, gamma) do
    cond do
      v == 0 -> 0.0
      v > 0 -> :math.pow(v, 1 / gamma)
      true -> -:math.pow(-v, 1 / gamma)
    end
  end

  @doc """
  Inverts simple gamma companding (non-linear → linear).

  ### Arguments

  * `v` is a companded channel value.

  * `gamma` is the gamma exponent.

  """
  def gamma_inverse_compand(v, gamma) do
    cond do
      v == 0 -> 0.0
      v > 0 -> :math.pow(v, gamma)
      true -> -:math.pow(-v, gamma)
    end
  end

  @doc """
  Applies the sRGB companding function (linear → sRGB).

  ### Arguments

  * `v` is a linear channel value in `[0, 1]`.

  """
  def srgb_compand(v) when v <= 0.0031308, do: 12.92 * v
  def srgb_compand(v), do: 1.055 * :math.pow(v, 1 / 2.4) - 0.055

  @doc """
  Inverts the sRGB companding function (sRGB → linear).

  ### Arguments

  * `v` is a companded sRGB channel value in `[0, 1]`.

  """
  def srgb_inverse_compand(v) when v <= 0.04045, do: v / 12.92
  def srgb_inverse_compand(v), do: :math.pow((v + 0.055) / 1.055, 2.4)

  @doc """
  Applies the L* companding function (linear → L*).

  ### Arguments

  * `v` is a linear channel value in `[0, 1]`.

  """
  def l_star_compand(v) when v <= @epsilon, do: v * @kappa / 100
  def l_star_compand(v), do: 1.16 * :math.pow(v, 1 / 3) - 0.16

  @doc """
  Inverts the L* companding function (L* → linear).

  ### Arguments

  * `v` is an L*-companded channel value.

  """
  def l_star_inverse_compand(v) when v <= 0.08, do: 100 * v / @kappa

  def l_star_inverse_compand(v) do
    t = (v + 0.16) / 1.16
    t * t * t
  end

  # ---------------------------------------------------------------------------
  # Rec. 709 / Rec. 2020 (SDR video) transfer functions
  # ---------------------------------------------------------------------------

  @doc """
  Applies the ITU-R BT.709 opto-electronic transfer function
  (linear → non-linear).

  BT.709 uses the same shape as the Rec. 2020 SDR curve but is defined
  at 8/10-bit precision; this implementation matches both.

  ### Arguments

  * `v` is a linear channel value in `[0, 1]`.

  """
  def rec709_compand(v) when v < 0.018, do: 4.5 * v
  def rec709_compand(v), do: 1.099 * :math.pow(v, 0.45) - 0.099

  @doc """
  Inverts the BT.709 OETF (non-linear → linear).

  ### Arguments

  * `v` is a non-linear BT.709 channel value in `[0, 1]`.

  """
  def rec709_inverse_compand(v) when v < 0.081, do: v / 4.5
  def rec709_inverse_compand(v), do: :math.pow((v + 0.099) / 1.099, 1 / 0.45)

  @doc """
  Applies the ITU-R BT.2020 OETF at 12-bit precision
  (linear → non-linear).

  BT.2020 refines the BT.709 curve with higher-precision constants for
  12-bit systems. At 10-bit precision BT.2020 is identical to BT.709.

  ### Arguments

  * `v` is a linear channel value in `[0, 1]`.

  """
  @alpha_2020 1.09929682680944
  @beta_2020 0.018053968510807
  def rec2020_compand(v) when v < @beta_2020, do: 4.5 * v

  def rec2020_compand(v) do
    @alpha_2020 * :math.pow(v, 0.45) - (@alpha_2020 - 1)
  end

  @doc """
  Inverts the BT.2020 12-bit OETF (non-linear → linear).

  ### Arguments

  * `v` is a non-linear BT.2020 channel value in `[0, 1]`.

  """
  def rec2020_inverse_compand(v) when v < 4.5 * @beta_2020, do: v / 4.5

  def rec2020_inverse_compand(v) do
    :math.pow((v + (@alpha_2020 - 1)) / @alpha_2020, 1 / 0.45)
  end

  # ---------------------------------------------------------------------------
  # Rec. 2100 HDR: PQ (SMPTE ST 2084) and HLG (Hybrid Log-Gamma)
  # ---------------------------------------------------------------------------

  # PQ constants (from SMPTE ST 2084 / Rec. ITU-R BT.2100)
  @pq_m1 0.1593017578125
  @pq_m2 78.84375
  @pq_c1 0.8359375
  @pq_c2 18.8515625
  @pq_c3 18.6875

  @doc """
  Applies the SMPTE ST 2084 / BT.2100 PQ inverse EOTF
  (linear luminance → non-linear PQ signal).

  Input is absolute luminance in `[0, 1]` where `1.0` represents
  10,000 cd/m². Output is the PQ-encoded signal in `[0, 1]`.

  ### Arguments

  * `v` is a linear luminance value in `[0, 1]`.

  """
  def pq_compand(v) when v <= 0, do: 0.0

  def pq_compand(v) do
    y = :math.pow(v, @pq_m1)
    :math.pow((@pq_c1 + @pq_c2 * y) / (1 + @pq_c3 * y), @pq_m2)
  end

  @doc """
  Applies the SMPTE ST 2084 / BT.2100 PQ EOTF
  (PQ signal → linear luminance in `[0, 1]` where `1.0` = 10,000 cd/m²).

  ### Arguments

  * `v` is a PQ-encoded value in `[0, 1]`.

  """
  def pq_inverse_compand(v) when v <= 0, do: 0.0

  def pq_inverse_compand(v) do
    ep = :math.pow(v, 1 / @pq_m2)
    num = max(ep - @pq_c1, 0)
    den = @pq_c2 - @pq_c3 * ep
    :math.pow(num / den, 1 / @pq_m1)
  end

  # HLG constants (from ARIB STD-B67 / ITU-R BT.2100)
  @hlg_a 0.17883277
  @hlg_b 0.28466892
  @hlg_c 0.55991073

  @doc """
  Applies the Hybrid Log-Gamma inverse EOTF
  (linear scene-referred light → HLG signal).

  Input and output are both in `[0, 1]`. The HLG curve is gamma at the
  dark end and logarithmic at the bright end, meeting at `E = 1/12`.

  ### Arguments

  * `v` is a linear channel value in `[0, 1]`.

  """
  def hlg_compand(v) when v <= 1 / 12, do: :math.sqrt(3 * v)
  def hlg_compand(v), do: @hlg_a * :math.log(12 * v - @hlg_b) + @hlg_c

  @doc """
  Applies the HLG EOTF (HLG signal → linear scene-referred light).

  ### Arguments

  * `v` is an HLG-encoded channel value in `[0, 1]`.

  """
  def hlg_inverse_compand(v) when v <= 0.5, do: v * v / 3
  def hlg_inverse_compand(v), do: (:math.exp((v - @hlg_c) / @hlg_a) + @hlg_b) / 12
end
