defmodule Color.LED do
  @moduledoc """
  Colour conversion for multi-channel addressable LEDs — fixtures
  with one or more extra **white** channels alongside R, G, B.

  Two channel layouts are supported:

  * **RGBW** — `Color.LED.RGBW`. Three coloured LEDs plus a single
    white LED per pixel. The white LED's colour temperature is fixed
    by the chip variant. Used by e.g. **WS2814** (warm, neutral and
    cool variants) and the SK6812-RGBW family.

  * **RGBWW** / **RGB+CCT** — `Color.LED.RGBWW`. Three coloured LEDs
    plus a **warm white** and a **cool white** LED per pixel. Used
    by e.g. **WS2805** and several SK6812 variants. The two whites
    can be blended to reach any CCT on the line between them.

  These structs are intentionally **device-referred**. They do
  not implement `Color.Behaviour` (which assumes a device-
  independent colour space with a single `from_xyz/1`) because
  converting *to* an RGBW/RGBWW pixel requires the white LED's
  colour temperature — there is no canonical answer without that
  parameter. Use `Color.LED.RGBW.from_srgb/2` and
  `Color.LED.RGBWW.from_srgb/2` explicitly.

  ## Channel semantics

  All channels — `r`, `g`, `b`, `w`, `ww`, `cw` — are **linear
  drive values in `[0.0, 1.0]`**, not sRGB-companded values. A
  value of `0.0` means "LED off"; `1.0` means "LED at full". The
  library applies sRGB companding when converting from a
  `Color.SRGB` struct, and un-compands back on the way out.

  The R/G/B primaries are assumed to match the sRGB working space
  (close enough for all WS281x / SK681x chips; exact for chips
  binned to sRGB). If you need a different primary set, stage the
  conversion through `Color.RGB` (linear, any working space) and
  then translate the matrix yourself.

  ## Extraction algorithm

  For RGBW, given a target linear-sRGB `(R, G, B)` and a white LED
  whose spectral output corresponds to linear-sRGB `(Rw, Gw, Bw)`
  at full drive, the extraction is:

      w = min(1, R/Rw, G/Gw, B/Bw)          (clamped to ≥ 0)
      r = R − w·Rw
      g = G − w·Gw
      b = B − w·Bw

  This maximises the white channel while keeping all RGB channels
  non-negative — more light from the (usually more efficient)
  white LED, less from the RGB LEDs.

  For RGBWW the algorithm first picks a blend ratio between the
  warm and cool whites matching the target's correlated colour
  temperature, synthesises an effective mixed white at that
  blend, then runs the RGBW extraction against that mixed white.
  The resulting total white is split back into `ww` and `cw` by
  the same ratio.

  ## Chip presets

  `chip_options/1` returns the default CCT options for the common
  chip variants:

  | Chip | Kind | Typical white temperature(s) |
  |---|---|---|
  | `:ws2814_ww` | RGBW | 3000 K (warm) |
  | `:ws2814_nw` | RGBW | 4500 K (neutral) |
  | `:ws2814_cw` | RGBW | 6000 K (cool) |
  | `:sk6812_ww` | RGBW | 3000 K |
  | `:sk6812_nw` | RGBW | 4500 K |
  | `:sk6812_cw` | RGBW | 6500 K |
  | `:ws2805`    | RGBWW | 3000 K warm + 6500 K cool |

  These are typical values from datasheets and vendor pages —
  actual parts vary by batch and binning. Measure yours if you
  need calibration-grade accuracy.

  ## Example

      # Build a pixel for a WS2805 fixture from an sRGB colour
      options = Color.LED.chip_options(:ws2805)
      {:ok, target} = Color.new("#ffa500")                 # orange
      pixel = Color.LED.RGBWW.from_srgb(target, options)
      # => %Color.LED.RGBWW{r: …, g: …, b: …, ww: …, cw: …,
      #                     warm_temperature: 3000,
      #                     cool_temperature: 6500,
      #                     alpha: nil}

      # Preview what the pixel will actually emit:
      {:ok, srgb_preview} = Color.LED.RGBWW.to_srgb(pixel)

  """

  @type chip ::
          :ws2814_ww
          | :ws2814_nw
          | :ws2814_cw
          | :sk6812_ww
          | :sk6812_nw
          | :sk6812_cw
          | :ws2805

  @chips %{
    ws2814_ww: [kind: :rgbw, white_temperature: 3000],
    ws2814_nw: [kind: :rgbw, white_temperature: 4500],
    ws2814_cw: [kind: :rgbw, white_temperature: 6000],
    sk6812_ww: [kind: :rgbw, white_temperature: 3000],
    sk6812_nw: [kind: :rgbw, white_temperature: 4500],
    sk6812_cw: [kind: :rgbw, white_temperature: 6500],
    ws2805: [kind: :rgbww, warm_temperature: 3000, cool_temperature: 6500]
  }

  @doc """
  Returns the recommended extraction options for a named LED chip
  variant.

  The returned keyword list can be passed directly to
  `Color.LED.RGBW.from_srgb/2` or `Color.LED.RGBWW.from_srgb/2` —
  the `:kind` entry tells you which one.

  ### Arguments

  * `chip` is a chip atom. See the chip table in the module doc.

  ### Returns

  * A keyword list with at least `:kind` (`:rgbw` or `:rgbww`)
    and the relevant temperature(s).

  ### Examples

      iex> Color.LED.chip_options(:ws2814_ww)
      [kind: :rgbw, white_temperature: 3000]

      iex> Color.LED.chip_options(:ws2805)
      [kind: :rgbww, warm_temperature: 3000, cool_temperature: 6500]

  """
  @spec chip_options(chip()) :: keyword()
  def chip_options(chip) when is_map_key(@chips, chip), do: Map.fetch!(@chips, chip)

  @doc """
  Returns the list of supported chip presets.

  ### Examples

      iex> :ws2814_nw in Color.LED.chips()
      true

      iex> :ws2805 in Color.LED.chips()
      true

  """
  @spec chips() :: [chip()]
  def chips, do: Map.keys(@chips) |> Enum.sort()

  # ---- internal helpers (shared by RGBW and RGBWW) ------------------------

  @doc false
  # Returns the linear-sRGB triple that represents the specified CCT
  # at relative luminance 1.0. This is the "direction" of that white
  # LED in linear sRGB: driving a white LED at full intensity emits
  # this much of each sRGB channel's equivalent light.
  def white_linear_rgb(cct) when is_number(cct) do
    xyz = Color.Temperature.xyz(cct, 1.0)
    {:ok, info} = Color.RGB.WorkingSpace.rgb_conversion_matrix(:SRGB)

    [[m11, m12, m13], [m21, m22, m23], [m31, m32, m33]] = info.from_xyz

    {
      m11 * xyz.x + m12 * xyz.y + m13 * xyz.z,
      m21 * xyz.x + m22 * xyz.y + m23 * xyz.z,
      m31 * xyz.x + m32 * xyz.y + m33 * xyz.z
    }
  end

  @doc false
  # Extracts the maximum amount of `white` from `(r, g, b)` linear
  # values such that r', g', b' all stay ≥ 0 and the white drive
  # stays ≤ 1.0.
  def extract_white({r, g, b}, {wr, wg, wb}) do
    candidates =
      [1.0]
      |> add_if_positive(wr, r)
      |> add_if_positive(wg, g)
      |> add_if_positive(wb, b)

    w = candidates |> Enum.min() |> max(0.0)

    {
      w,
      {
        max(0.0, r - w * wr),
        max(0.0, g - w * wg),
        max(0.0, b - w * wb)
      }
    }
  end

  defp add_if_positive(list, denom, num) when denom > 0, do: [num / denom | list]
  defp add_if_positive(list, _, _), do: list

  @doc false
  # Linearise a Color.SRGB to a `{r, g, b}` triple in linear sRGB.
  def linearise(%Color.SRGB{r: r, g: g, b: b}) do
    {
      Color.Conversion.Lindbloom.srgb_inverse_compand(r),
      Color.Conversion.Lindbloom.srgb_inverse_compand(g),
      Color.Conversion.Lindbloom.srgb_inverse_compand(b)
    }
  end

  @doc false
  # Companded sRGB from a linear triple, clamped to [0, 1].
  def compand({r, g, b}, alpha) do
    %Color.SRGB{
      r: Color.Conversion.Lindbloom.srgb_compand(clamp(r)),
      g: Color.Conversion.Lindbloom.srgb_compand(clamp(g)),
      b: Color.Conversion.Lindbloom.srgb_compand(clamp(b)),
      alpha: alpha
    }
  end

  @doc false
  def clamp(v) when v < 0, do: 0.0
  def clamp(v) when v > 1, do: 1.0
  def clamp(v), do: v
end
