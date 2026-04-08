defmodule Color.ICtCp do
  @moduledoc """
  ICtCp color space (ITU-R BT.2100).

  ICtCp is the HDR/WCG color space used by Dolby Vision, HDR10+ and
  Rec. 2100. It operates on Rec. 2020 primaries with either the PQ
  (default) or HLG transfer function. Use PQ for cinema/OTT, HLG for
  broadcast.

  The `:transfer` field selects the transfer function — `:pq`
  (default) or `:hlg`.

  PQ is an absolute transfer function: input `1.0` corresponds to
  10,000 cd/m². Since our `Color.XYZ` uses `Y = 1.0` for the reference
  white, we scale by a `:reference_luminance` option (default
  `100` cd/m², matching SDR diffuse white) before encoding and
  divide on the way back.

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Lindbloom

  defstruct [:i, :ct, :cp, :alpha, transfer: :pq]

  @typedoc """
  An ITP (ICtCp) colour for HDR signals (Rec. 2100). `i` is intensity,
  `ct` and `cp` are the tritan / protan chroma channels. The
  `:transfer` field selects PQ (`:pq`, the default) or HLG (`:hlg`).
  """
  @type t :: %__MODULE__{
          i: float() | nil,
          ct: float() | nil,
          cp: float() | nil,
          alpha: Color.Types.alpha(),
          transfer: :pq | :hlg
        }

  # Rec.2020 linear RGB -> LMS (from BT.2100)
  @rgb_to_lms [
    [1688 / 4096, 2146 / 4096, 262 / 4096],
    [683 / 4096, 2951 / 4096, 462 / 4096],
    [99 / 4096, 309 / 4096, 3688 / 4096]
  ]

  @lms_to_rgb Lindbloom.invert3(@rgb_to_lms)

  # LMS' -> ICtCp (BT.2100)
  @lms_to_ictcp [
    [0.5, 0.5, 0.0],
    [6610 / 4096, -13_613 / 4096, 7003 / 4096],
    [17_933 / 4096, -17_390 / 4096, -543 / 4096]
  ]

  @ictcp_to_lms Lindbloom.invert3(@lms_to_ictcp)

  @doc """
  Converts CIE `XYZ` (D65) to ICtCp using the PQ transfer function.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.ICtCp` struct with `transfer: :pq`.

  ### Examples

      iex> {:ok, ictcp} = Color.ICtCp.from_xyz(%Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2})
      iex> Float.round(ictcp.i, 3)
      0.508

  """
  def from_xyz(xyz, options \\ [])

  def from_xyz(%Color.XYZ{} = xyz, options) do
    transfer = Keyword.get(options, :transfer, :pq)
    ref = Keyword.get(options, :reference_luminance, 100)
    scale = ref / 10_000

    with {:ok, rgb} <- Color.RGB.from_xyz(xyz, :Rec2020) do
      lms_raw = Lindbloom.rgb_to_xyz({rgb.r, rgb.g, rgb.b}, @rgb_to_lms)
      lms_scaled = scale_triple(lms_raw, scale)
      lms_p = encode_triple(lms_scaled, transfer)
      {i, ct, cp} = Lindbloom.rgb_to_xyz(lms_p, @lms_to_ictcp)

      {:ok, %__MODULE__{i: i, ct: ct, cp: cp, alpha: rgb.alpha, transfer: transfer}}
    end
  end

  @doc """
  Converts ICtCp to CIE `XYZ` (D65).

  """
  def to_xyz(ictcp, options \\ [])

  def to_xyz(%__MODULE__{i: i, ct: ct, cp: cp, alpha: alpha, transfer: transfer}, options) do
    ref = Keyword.get(options, :reference_luminance, 100)
    scale = ref / 10_000

    lms_p = Lindbloom.rgb_to_xyz({i, ct, cp}, @ictcp_to_lms)
    lms_scaled = decode_triple(lms_p, transfer)
    lms = scale_triple(lms_scaled, 1 / scale)
    {r, g, b} = Lindbloom.rgb_to_xyz(lms, @lms_to_rgb)

    Color.RGB.to_xyz(%Color.RGB{r: r, g: g, b: b, alpha: alpha, working_space: :Rec2020})
  end

  defp scale_triple({a, b, c}, s), do: {a * s, b * s, c * s}

  defp encode_triple({a, b, c}, :pq),
    do: {
      Lindbloom.pq_compand(a),
      Lindbloom.pq_compand(b),
      Lindbloom.pq_compand(c)
    }

  defp encode_triple({a, b, c}, :hlg),
    do: {
      Lindbloom.hlg_compand(a),
      Lindbloom.hlg_compand(b),
      Lindbloom.hlg_compand(c)
    }

  defp decode_triple({a, b, c}, :pq),
    do: {
      Lindbloom.pq_inverse_compand(a),
      Lindbloom.pq_inverse_compand(b),
      Lindbloom.pq_inverse_compand(c)
    }

  defp decode_triple({a, b, c}, :hlg),
    do: {
      Lindbloom.hlg_inverse_compand(a),
      Lindbloom.hlg_inverse_compand(b),
      Lindbloom.hlg_inverse_compand(c)
    }
end
