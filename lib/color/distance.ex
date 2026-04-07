defmodule Color.Distance do
  @moduledoc """
  Color difference (ΔE) metrics between two colors.

  Each function accepts two colors in any supported color space; inputs
  that are not already in `L*a*b*` are converted via `Color.convert/2`,
  chromatically adapting to D65 as necessary.

  The supported metrics are:

  * `delta_e_76/2` — CIE76, the original simple Euclidean distance in
    `L*a*b*`. Fast but known to be perceptually non-uniform, especially
    in saturated blue-purple regions.

  * `delta_e_94/3` — CIE94, a weighted distance that corrects the
    saturation/hue issues of CIE76. Parametric factors default to the
    graphic-arts application (`kL = 1, K1 = 0.045, K2 = 0.015`).

  * `delta_e_2000/3` — CIEDE2000, the modern standard. Much more
    complex but handles perceptual non-uniformity well.

  * `delta_e_cmc/3` — CMC l:c, developed by the Colour Measurement
    Committee of the Society of Dyers and Colourists. Common in the
    textile industry.

  For most use cases prefer `delta_e_2000/3`.

  """

  alias Color.Lab

  @doc """
  CIE76 color difference — Euclidean distance in `L*a*b*`.

  ### Arguments

  * `a` is any supported color.

  * `b` is any supported color.

  ### Returns

  * A non-negative float.

  ### Examples

      iex> Color.Distance.delta_e_76(%Color.Lab{l: 50.0, a: 0.0, b: 0.0}, %Color.Lab{l: 50.0, a: 0.0, b: 0.0})
      0.0

      iex> Float.round(Color.Distance.delta_e_76(%Color.Lab{l: 50.0, a: 2.6772, b: -79.7751}, %Color.Lab{l: 50.0, a: 0.0, b: -82.7485}), 4)
      4.0011

  """
  def delta_e_76(a, b) do
    {l1, a1, b1} = lab_triple(a)
    {l2, a2, b2} = lab_triple(b)

    dl = l1 - l2
    da = a1 - a2
    db = b1 - b2

    :math.sqrt(dl * dl + da * da + db * db)
  end

  @doc """
  CIE94 color difference.

  ### Arguments

  * `a` is any supported color.

  * `b` is any supported color.

  * `options` is a keyword list.

  ### Options

  * `:application` is `:graphic_arts` (default) or `:textiles` and
    picks the CIE94 `kL`, `K1`, `K2` constants.

  * `:kL`, `:kC`, `:kH` are parametric weighting factors (defaults
    `1.0, 1.0, 1.0`).

  ### Returns

  * A non-negative float.

  ### Examples

      iex> Float.round(Color.Distance.delta_e_94(%Color.Lab{l: 50.0, a: 2.6772, b: -79.7751}, %Color.Lab{l: 50.0, a: 0.0, b: -82.7485}), 4)
      1.3950

  """
  def delta_e_94(a, b, options \\ []) do
    {k_l, k1, k2} =
      case Keyword.get(options, :application, :graphic_arts) do
        :graphic_arts -> {1.0, 0.045, 0.015}
        :textiles -> {2.0, 0.048, 0.014}
      end

    k_l = Keyword.get(options, :kL, k_l)
    k_c = Keyword.get(options, :kC, 1.0)
    k_h = Keyword.get(options, :kH, 1.0)

    {l1, a1, b1} = lab_triple(a)
    {l2, a2, b2} = lab_triple(b)

    c1 = :math.sqrt(a1 * a1 + b1 * b1)
    c2 = :math.sqrt(a2 * a2 + b2 * b2)

    dl = l1 - l2
    dc = c1 - c2
    da = a1 - a2
    db = b1 - b2
    dh_sq = da * da + db * db - dc * dc
    dh_sq = if dh_sq < 0, do: 0.0, else: dh_sq

    s_l = 1.0
    s_c = 1.0 + k1 * c1
    s_h = 1.0 + k2 * c1

    t1 = dl / (k_l * s_l)
    t2 = dc / (k_c * s_c)
    t3 = :math.sqrt(dh_sq) / (k_h * s_h)

    :math.sqrt(t1 * t1 + t2 * t2 + t3 * t3)
  end

  @doc """
  CIEDE2000 color difference.

  Reference: Sharma, Wu & Dalal, "The CIEDE2000 Color-Difference
  Formula: Implementation Notes, Supplementary Test Data, and
  Mathematical Observations" (2005).

  ### Arguments

  * `a` is any supported color.

  * `b` is any supported color.

  * `options` is a keyword list.

  ### Options

  * `:kL`, `:kC`, `:kH` are parametric weighting factors (defaults
    `1.0, 1.0, 1.0`).

  ### Returns

  * A non-negative float.

  ### Examples

      iex> Float.round(Color.Distance.delta_e_2000(%Color.Lab{l: 50.0, a: 2.6772, b: -79.7751}, %Color.Lab{l: 50.0, a: 0.0, b: -82.7485}), 4)
      2.0425

      iex> Float.round(Color.Distance.delta_e_2000(%Color.Lab{l: 50.0, a: 2.5, b: 0.0}, %Color.Lab{l: 73.0, a: 25.0, b: -18.0}), 4)
      27.1492

  """
  def delta_e_2000(a, b, options \\ []) do
    k_l = Keyword.get(options, :kL, 1.0)
    k_c = Keyword.get(options, :kC, 1.0)
    k_h = Keyword.get(options, :kH, 1.0)

    {l1, a1, b1} = lab_triple(a)
    {l2, a2, b2} = lab_triple(b)

    c1_star = :math.sqrt(a1 * a1 + b1 * b1)
    c2_star = :math.sqrt(a2 * a2 + b2 * b2)
    c_bar = (c1_star + c2_star) / 2

    c_bar_7 = :math.pow(c_bar, 7)
    g = 0.5 * (1 - :math.sqrt(c_bar_7 / (c_bar_7 + :math.pow(25, 7))))

    a1p = (1 + g) * a1
    a2p = (1 + g) * a2

    c1p = :math.sqrt(a1p * a1p + b1 * b1)
    c2p = :math.sqrt(a2p * a2p + b2 * b2)

    h1p = hue_deg(b1, a1p)
    h2p = hue_deg(b2, a2p)

    dlp = l2 - l1
    dcp = c2p - c1p

    dhp =
      cond do
        c1p * c2p == 0 -> 0.0
        abs(h2p - h1p) <= 180 -> h2p - h1p
        h2p - h1p > 180 -> h2p - h1p - 360
        true -> h2p - h1p + 360
      end

    big_dhp = 2 * :math.sqrt(c1p * c2p) * :math.sin(deg_to_rad(dhp) / 2)

    lp_bar = (l1 + l2) / 2
    cp_bar = (c1p + c2p) / 2

    hp_bar =
      cond do
        c1p * c2p == 0 -> h1p + h2p
        abs(h1p - h2p) <= 180 -> (h1p + h2p) / 2
        h1p + h2p < 360 -> (h1p + h2p + 360) / 2
        true -> (h1p + h2p - 360) / 2
      end

    t =
      1 - 0.17 * :math.cos(deg_to_rad(hp_bar - 30)) +
        0.24 * :math.cos(deg_to_rad(2 * hp_bar)) +
        0.32 * :math.cos(deg_to_rad(3 * hp_bar + 6)) -
        0.20 * :math.cos(deg_to_rad(4 * hp_bar - 63))

    delta_theta = 30 * :math.exp(-:math.pow((hp_bar - 275) / 25, 2))
    cp_bar_7 = :math.pow(cp_bar, 7)
    r_c = 2 * :math.sqrt(cp_bar_7 / (cp_bar_7 + :math.pow(25, 7)))
    s_l = 1 + 0.015 * :math.pow(lp_bar - 50, 2) / :math.sqrt(20 + :math.pow(lp_bar - 50, 2))
    s_c = 1 + 0.045 * cp_bar
    s_h = 1 + 0.015 * cp_bar * t
    r_t = -:math.sin(2 * deg_to_rad(delta_theta)) * r_c

    term_l = dlp / (k_l * s_l)
    term_c = dcp / (k_c * s_c)
    term_h = big_dhp / (k_h * s_h)

    :math.sqrt(term_l * term_l + term_c * term_c + term_h * term_h + r_t * term_c * term_h)
  end

  @doc """
  CMC l:c color difference.

  ### Arguments

  * `a` is any supported color.

  * `b` is any supported color.

  * `options` is a keyword list.

  ### Options

  * `:l` is the lightness weighting factor. Defaults to `2.0`
    (acceptability). Use `1.0` for perceptibility.

  * `:c` is the chroma weighting factor. Defaults to `1.0`.

  ### Returns

  * A non-negative float.

  ### Examples

      iex> Float.round(Color.Distance.delta_e_cmc(%Color.Lab{l: 50.0, a: 2.6772, b: -79.7751}, %Color.Lab{l: 50.0, a: 0.0, b: -82.7485}), 4)
      1.7387

  """
  def delta_e_cmc(a, b, options \\ []) do
    l_w = Keyword.get(options, :l, 2.0)
    c_w = Keyword.get(options, :c, 1.0)

    {l1, a1, b1} = lab_triple(a)
    {l2, a2, b2} = lab_triple(b)

    c1 = :math.sqrt(a1 * a1 + b1 * b1)
    c2 = :math.sqrt(a2 * a2 + b2 * b2)

    dl = l1 - l2
    dc = c1 - c2
    da = a1 - a2
    db = b1 - b2
    dh_sq = da * da + db * db - dc * dc
    dh_sq = if dh_sq < 0, do: 0.0, else: dh_sq

    h1 = hue_deg(b1, a1)

    s_l =
      if l1 < 16 do
        0.511
      else
        0.040975 * l1 / (1 + 0.01765 * l1)
      end

    s_c = 0.0638 * c1 / (1 + 0.0131 * c1) + 0.638
    c1_4 = :math.pow(c1, 4)
    f = :math.sqrt(c1_4 / (c1_4 + 1900))

    t =
      if h1 >= 164 and h1 <= 345 do
        0.56 + abs(0.2 * :math.cos(deg_to_rad(h1 + 168)))
      else
        0.36 + abs(0.4 * :math.cos(deg_to_rad(h1 + 35)))
      end

    s_h = s_c * (f * t + 1 - f)

    t1 = dl / (l_w * s_l)
    t2 = dc / (c_w * s_c)
    t3 = :math.sqrt(dh_sq) / s_h

    :math.sqrt(t1 * t1 + t2 * t2 + t3 * t3)
  end

  defp lab_triple(%Lab{l: l, a: a, b: b}), do: {l, a, b}

  defp lab_triple(other) do
    {:ok, lab} = Color.convert(other, Lab)
    {lab.l, lab.a, lab.b}
  end

  defp hue_deg(b, a) do
    case :math.atan2(b, a) * 180 / :math.pi() do
      h when h < 0 -> h + 360
      h -> h
    end
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180
end
