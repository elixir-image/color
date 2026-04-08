defmodule Color.CAM16UCS do
  @moduledoc """
  CAM16-UCS perceptual color space.

  CAM16 is a full color appearance model (Li et al. 2017, an update of
  CIECAM02). CAM16-UCS is its uniform-color-space projection —
  a `(J', a', b')` triple where equal Euclidean distance corresponds
  to equal perceptual difference, even better than CIELAB.

  Conversions assume standard default viewing conditions:

  * Reference white: D65.

  * Adapting luminance `L_A = 64 / π / 5 ≈ 4.074` cd/m².

  * Background relative luminance `Y_b = 20`.

  * Average surround (`F = 1.0`, `c = 0.69`, `N_c = 1.0`).

  If you need non-default viewing conditions you can pass them as
  options.

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Lindbloom

  defstruct [:j, :a, :b, :alpha]

  @typedoc """
  A `Color.CAM16UCS` colour. The CAM16-UCS uniform space coordinates:
  `j` is lightness in `[0, 100]`, `a` and `b` are red-green and
  yellow-blue chromatic coordinates.
  """
  @type t :: %__MODULE__{
          j: float() | nil,
          a: float() | nil,
          b: float() | nil,
          alpha: Color.Types.alpha()
        }

  # CAT16 cone matrix
  @mcat16 [
    [0.401288, 0.650173, -0.051461],
    [-0.250268, 1.204414, 0.045854],
    [-0.002079, 0.048952, 0.953127]
  ]

  @mcat16_inv Lindbloom.invert3(@mcat16)

  @default_xyz_w {95.047, 100.0, 108.883}
  @default_la 64 / :math.pi() / 5
  @default_yb 20.0
  @default_surround {1.0, 0.69, 1.0}

  @doc """
  Converts CIE `XYZ` (D65, `Y ∈ [0, 1]`) to CAM16-UCS.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  * `options` is a keyword list.

  ### Options

  * `:viewing_conditions` is a map with `:xyz_w`, `:la`, `:yb`, and
    `:surround`. Defaults to D65 / `L_A = 4.074` / `Y_b = 20` / average.

  ### Returns

  * A `Color.CAM16UCS` struct where `j` is `J'`, `a` is `a'`, `b` is
    `b'`.

  ### Examples

      iex> {:ok, ucs} = Color.CAM16UCS.from_xyz(%Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2})
      iex> {Float.round(ucs.j, 2), :math.sqrt(ucs.a * ucs.a + ucs.b * ucs.b) < 3.0}
      {100.0, true}

  """
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}, options \\ []) do
    vc = viewing_conditions(options)

    # Scale to 0..100 to match the standard CAM16 Y_w = 100
    {j, a, b} = xyz_to_cam16_ucs({x * 100, y * 100, z * 100}, vc)
    {:ok, %__MODULE__{j: j, a: a, b: b, alpha: alpha}}
  end

  @doc """
  Converts CAM16-UCS to CIE `XYZ` (D65, `Y ∈ [0, 1]`).

  ### Arguments

  * `ucs` is a `Color.CAM16UCS` struct.

  * `options` is a keyword list (see `from_xyz/2`).

  ### Returns

  * A `Color.XYZ` struct tagged D65/2°.

  """
  def to_xyz(%__MODULE__{j: jp, a: ap, b: bp, alpha: alpha}, options \\ []) do
    vc = viewing_conditions(options)
    {x, y, z} = cam16_ucs_to_xyz({jp, ap, bp}, vc)

    {:ok,
     %Color.XYZ{
       x: x / 100,
       y: y / 100,
       z: z / 100,
       alpha: alpha,
       illuminant: :D65,
       observer_angle: 2
     }}
  end

  # ---- forward ---------------------------------------------------------------

  defp xyz_to_cam16_ucs({x, y, z}, vc) do
    %{
      d_r: d_r,
      d_g: d_g,
      d_b: d_b,
      fl: fl,
      n: n,
      nbb: nbb,
      ncb: ncb,
      z_exp: z_exp,
      a_w: a_w,
      c: c,
      nc: nc
    } = vc

    {r, g, b} = Lindbloom.rgb_to_xyz({x, y, z}, @mcat16)
    rc = d_r * r
    gc = d_g * g
    bc = d_b * b

    ra = adapt_channel(rc, fl)
    ga = adapt_channel(gc, fl)
    ba = adapt_channel(bc, fl)

    a = ra - 12 * ga / 11 + ba / 11
    b = (ra + ga - 2 * ba) / 9

    h = hue_deg(b, a)
    h_rad = h * :math.pi() / 180

    aa_big = (2 * ra + ga + ba / 20 - 0.305) * nbb
    j = 100 * :math.pow(max(aa_big / a_w, 0), c * z_exp)

    et = (:math.cos(h_rad + 2) + 3.8) / 4

    t =
      50_000 / 13 * nc * ncb * et * :math.sqrt(a * a + b * b) /
        (ra + ga + 21 * ba / 20)

    c_cam =
      :math.pow(max(t, 0), 0.9) * :math.sqrt(max(j, 0) / 100) *
        :math.pow(1.64 - :math.pow(0.29, n), 0.73)

    m = c_cam * :math.pow(fl, 0.25)

    jp = 1.7 * j / (1 + 0.007 * j)
    mp = :math.log(1 + 0.0228 * m) / 0.0228
    ap = mp * :math.cos(h_rad)
    bp = mp * :math.sin(h_rad)

    {jp, ap, bp}
  end

  # ---- inverse ---------------------------------------------------------------

  defp cam16_ucs_to_xyz({jp, ap, bp}, vc) do
    %{
      d_r: d_r,
      d_g: d_g,
      d_b: d_b,
      fl: fl,
      n: n,
      nbb: nbb,
      ncb: ncb,
      z_exp: z_exp,
      a_w: a_w,
      c: c,
      nc: nc
    } = vc

    mp = :math.sqrt(ap * ap + bp * bp)
    m = (:math.exp(0.0228 * mp) - 1) / 0.0228
    c_cam = m / :math.pow(fl, 0.25)

    h_rad = :math.atan2(bp, ap)

    j =
      if jp <= 0 do
        0.0
      else
        jp / (1.7 - 0.007 * jp)
      end

    # Recover t from C
    denom = :math.sqrt(max(j, 0) / 100) * :math.pow(1.64 - :math.pow(0.29, n), 0.73)

    t =
      if denom == 0 do
        0.0
      else
        :math.pow(c_cam / denom, 1 / 0.9)
      end

    et = 0.25 * (:math.cos(h_rad + 2) + 3.8)
    aa_big = :math.pow(max(j, 0) / 100, 1 / (c * z_exp)) * a_w

    p2 = aa_big / nbb + 0.305
    p3 = 21 / 20

    {a, b} =
      if t == 0 do
        {0.0, 0.0}
      else
        # p1 = (50000/13) * Nc * Ncb * e_t / t  (Li et al. 2017, CAM16 inverse)
        p1 = 50_000 / 13 * nc * ncb * et / t
        hs = :math.sin(h_rad)
        hc = :math.cos(h_rad)

        if abs(hs) >= abs(hc) do
          p4 = p1 / hs

          b =
            p2 * (2 + p3) * (460 / 1403) /
              (p4 + (2 + p3) * (220 / 1403) * (hc / hs) -
                 27 / 1403 + p3 * (6300 / 1403))

          a = b * hc / hs
          {a, b}
        else
          p5 = p1 / hc

          a =
            p2 * (2 + p3) * (460 / 1403) /
              (p5 + (2 + p3) * (220 / 1403) -
                 (27 / 1403 - p3 * (6300 / 1403)) * (hs / hc))

          b = a * hs / hc
          {a, b}
        end
      end

    # Solve for Ra, Ga, Ba
    ra = 460 / 1403 * p2 + 451 / 1403 * a + 288 / 1403 * b
    ga = 460 / 1403 * p2 - 891 / 1403 * a - 261 / 1403 * b
    ba = 460 / 1403 * p2 - 220 / 1403 * a - 6300 / 1403 * b

    # Invert the post-adaptation non-linearity
    rc = inverse_adapt_channel(ra, fl)
    gc = inverse_adapt_channel(ga, fl)
    bc = inverse_adapt_channel(ba, fl)

    r = rc / d_r
    g = gc / d_g
    b_lms = bc / d_b

    Lindbloom.rgb_to_xyz({r, g, b_lms}, @mcat16_inv)
  end

  # ---- helpers ---------------------------------------------------------------

  defp viewing_conditions(options) do
    xyz_w = Keyword.get(options, :xyz_w, @default_xyz_w)
    la = Keyword.get(options, :la, @default_la)
    yb = Keyword.get(options, :yb, @default_yb)
    {f, c, nc} = Keyword.get(options, :surround, @default_surround)

    {xw, yw, zw} = xyz_w
    {rw, gw, bw} = Lindbloom.rgb_to_xyz({xw, yw, zw}, @mcat16)

    d_base = f * (1 - 1 / 3.6 * :math.exp((-la - 42) / 92))
    d = min(max(d_base, 0.0), 1.0)
    d_r = d * yw / rw + 1 - d
    d_g = d * yw / gw + 1 - d
    d_b = d * yw / bw + 1 - d

    k = 1 / (5 * la + 1)

    fl =
      0.2 * :math.pow(k, 4) * 5 * la +
        0.1 * :math.pow(1 - :math.pow(k, 4), 2) *
          :math.pow(5 * la, 1 / 3)

    n = yb / yw
    z_exp = 1.48 + :math.sqrt(n)
    nbb = 0.725 * :math.pow(1 / n, 0.2)
    ncb = nbb

    # Compute A for the white point
    rwc = d_r * rw
    gwc = d_g * gw
    bwc = d_b * bw
    raw = adapt_channel(rwc, fl)
    gaw = adapt_channel(gwc, fl)
    baw = adapt_channel(bwc, fl)
    a_w = (2 * raw + gaw + baw / 20 - 0.305) * nbb

    %{
      d_r: d_r,
      d_g: d_g,
      d_b: d_b,
      fl: fl,
      n: n,
      nbb: nbb,
      ncb: ncb,
      z_exp: z_exp,
      a_w: a_w,
      c: c,
      nc: nc
    }
  end

  defp adapt_channel(v, fl) do
    s = if v >= 0, do: 1, else: -1
    x = :math.pow(fl * abs(v) / 100, 0.42)
    s * 400 * x / (x + 27.13) + 0.1
  end

  defp inverse_adapt_channel(v, fl) do
    u = v - 0.1
    s = if u >= 0, do: 1, else: -1
    abs_u = abs(u)

    if 400 - abs_u <= 0 do
      s * 0.0
    else
      t = 27.13 * abs_u / (400 - abs_u)
      s * 100 / fl * :math.pow(t, 1 / 0.42)
    end
  end

  defp hue_deg(b, a) do
    case :math.atan2(b, a) * 180 / :math.pi() do
      h when h < 0 -> h + 360
      h -> h
    end
  end
end
