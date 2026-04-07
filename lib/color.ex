defmodule Color do
  @moduledoc """
  Top-level color conversion dispatch.

  Every color struct in this library implements `to_xyz/1` and
  `from_xyz/1`. `convert/2` and `convert/3` use `Color.XYZ` as the hub:
  any source color is converted to `XYZ`, then converted to the
  requested target color.

  The color spaces currently supported are:

  * `Color.XYZ` — CIE 1931 tristimulus.

  * `Color.XYY` — CIE xyY (chromaticity + luminance).

  * `Color.Lab` — CIE 1976 `L*a*b*`.

  * `Color.LCHab` — cylindrical `L*a*b*`.

  * `Color.Luv` — CIE 1976 `L*u*v*`.

  * `Color.LCHuv` — cylindrical `L*u*v*`.

  * `Color.Oklab` — Oklab perceptual color space (Björn Ottosson, 2020),
    defined against D65.

  * `Color.Oklch` — cylindrical Oklab.

  * `Color.HSLuv` / `Color.HPLuv` — perceptually-uniform HSL variants
    built on CIELUV (Boronine 2015).

  * `Color.JzAzBz` — HDR/wide-gamut perceptual space (Safdar et al. 2017).

  * `Color.ICtCp` — Rec. 2100 HDR (PQ or HLG).

  * `Color.IPT` — Ebner & Fairchild 1998, ancestor of Oklab.

  * `Color.CAM16UCS` — CAM16 Color Appearance Model uniform space.

  * `Color.CMYK` — simple subtractive (no ICC).

  * `Color.YCbCr` — digital video with BT.601/709/2020 variants.

  * `Color.SRGB` — companded sRGB working space (D65).

  * `Color.AdobeRGB` — companded Adobe RGB (1998) working space (D65).

  * `Color.RGB` — linear RGB in any named working space.

  * `Color.Hsl`, `Color.Hsv` — non-linear reparameterisations of sRGB.

  All struct modules also expose their own `to_xyz/1` and `from_xyz/1`
  functions directly if you want to skip dispatch.

  ## Building colors with `new/1` and `new/2`

  `new/1` and `new/2` accept any of:

  * A color struct (passed through unchanged, second argument ignored).

  * A hex string (`"#ff0000"`, `"#f80"`, `"#ff000080"`, with or without
    the leading `#`) or a CSS named color (`"rebeccapurple"`).

  * A bare list of 3, 4, or 5 numbers, interpreted as the color space
    given by the optional second argument (default `:srgb`).

  `convert/2` and `convert/3` accept the same inputs, so you can write
  `Color.convert([1.0, 0.0, 0.0], Color.Lab)` without first wrapping
  the list in an `SRGB` struct.

  ### Color space argument

  The second argument to `new/2` (and the `space` implicitly passed
  through `convert/2,3`) is either a short atom or the module for a
  supported color space. The recognised aliases are:

  | Short atom | Module | Notes |
  |---|---|---|
  | `:srgb` | `Color.SRGB` | default |
  | `:adobe_rgb` / `:adobe` | `Color.AdobeRGB` | |
  | `:cmyk` | `Color.CMYK` | 4 or 5 channels |
  | `:hsl` | `Color.Hsl` | hue in `[0, 1]` |
  | `:hsv` | `Color.Hsv` | hue in `[0, 1]` |
  | `:hsluv` | `Color.HSLuv` | hue in degrees, s/l in `[0, 100]` |
  | `:hpluv` | `Color.HPLuv` | hue in degrees, s/l in `[0, 100]` |
  | `:lab` | `Color.Lab` | D65 |
  | `:lch` / `:lchab` | `Color.LCHab` | D65 |
  | `:luv` | `Color.Luv` | D65 |
  | `:lchuv` | `Color.LCHuv` | D65 |
  | `:oklab` | `Color.Oklab` | D65 |
  | `:oklch` | `Color.Oklch` | D65 |
  | `:xyz` | `Color.XYZ` | D65 / 2° |
  | `:xyy` / `:xyY` | `Color.XYY` | D65 / 2° |
  | `:jzazbz` | `Color.JzAzBz` | |
  | `:ictcp` | `Color.ICtCp` | defaults to `transfer: :pq` |
  | `:ipt` | `Color.IPT` | |
  | `:ycbcr` | `Color.YCbCr` | defaults to `variant: :bt709` |
  | `:cam16` / `:cam16_ucs` | `Color.CAM16UCS` | default viewing conditions |

  `Color.RGB` (linear, any working space) is intentionally **not**
  list-constructible via `new/2` — use
  `Color.convert([1.0, 1.0, 1.0], Color.RGB, :Rec2020)` instead.

  ### Validation rules for list inputs

  Validation depends on the space. The table below is the complete
  specification:

  | Category | Spaces | Integer form? | Range check |
  |---|---|---|---|
  | **Strict display** | `:srgb`, `:adobe_rgb`, `:cmyk` | Yes — `0..255`, scaled to `[0.0, 1.0]` | Strict — each channel must be in its exact range |
  | **Strict unit cylindrical** | `:hsl`, `:hsv` | No | Strict — all channels in `[0.0, 1.0]`, hue wraps |
  | **Strict deg/percent cylindrical** | `:hsluv`, `:hpluv` | No | Strict — `h` wraps, `s` and `l` must be in `[0, 100]` |
  | **Permissive 3-channel** | `:lab`, `:luv`, `:oklab`, `:jzazbz`, `:ipt`, `:xyz`, `:xyy`, `:ictcp`, `:ycbcr`, `:cam16_ucs` | No | None — accepts wide-gamut / HDR values; rejects `NaN` and `±∞` |
  | **Permissive cylindrical** | `:lch`, `:lchuv`, `:oklch` | No | None — hue wraps to `[0, 360)`, other channels unrestricted |

  Additional rules that apply across the board:

  * The list is always either 3 or 4 numbers, with 4 meaning "plus
    alpha". `:cmyk` additionally accepts 5 numbers (c, m, y, k,
    alpha).

  * In the **strict display** category, the list must be **uniform**:
    either all integers (assumed `0..255`) or all floats (assumed
    `[0.0, 1.0]`). Mixing integers and floats is an error. Integer
    alpha is also assumed to be `0..255`.

  * **Integer form is only accepted for the three strict display RGB
    spaces.** Every other space rejects integer lists with a clear
    error pointing to the float form.

  * **Permissive validation accepts out-of-nominal-range values**
    because wide-gamut and HDR sources legitimately exceed the
    textbook ranges (e.g. wide-gamut Lab can exceed ±128, HDR Oklab
    can exceed ±0.4, HDR XYZ can exceed `Y = 1.0`). It still rejects
    `NaN` and infinity.

  * **Cylindrical hues are normalised, not errored.** `oklch [0.7,
    0.2, 390.0]` becomes `h = 30.0`, and `oklch [0.7, 0.2, -45.0]`
    becomes `h = 315.0`. The same applies to HSL/HSV hue in `[0, 1]`.

  * **CIE-tagged spaces default to D65 / 2° observer.** If you need a
    different illuminant, construct the struct directly or use
    `Color.XYZ.adapt/3` after the fact.

  ## Alpha

  Every color struct has an `:alpha` field. Alpha is passed straight
  through every conversion — it is never touched by the color math
  itself. The library's API assumes **straight** (unassociated) alpha.
  If you are working with pre-multiplied pixel data, un-premultiply
  before converting (see the "Pre-multiplied alpha" section below and
  `Color.unpremultiply/1` / `Color.premultiply/1`) and re-multiply
  afterwards.

  ## Pre-multiplied alpha

  Pre-multiplied alpha matters only when a color space's transfer
  function is **non-linear** with respect to the RGB channels. In a
  pre-multiplied pixel `(R·a, G·a, B·a, a)`, the stored channels are
  no longer the pixel's true color — they are the color scaled by its
  own coverage. Applying a non-linear operation like sRGB companding
  to `R·a` does not give you `sRGB(R)·a` because
  `(R·a)^γ ≠ R^γ · a^γ`.

  Since this library's forward pipeline is always
  `source → linear RGB → XYZ → target`, and several stages contain
  non-linear steps (sRGB companding, Adobe RGB gamma, the PQ / HLG
  transfer functions, Lab's `f(x)`, Oklab's cube root, CAM16's
  post-adaptation compression, etc.), converting a pre-multiplied
  color directly is **incorrect** and will produce subtly wrong
  output.

  The rule is:

  1. If your color is straight-alpha: just call `convert/2`. The alpha
     value is carried through untouched.

  2. If your color is pre-multiplied: call `Color.unpremultiply/1`,
     then `convert/2`, then `Color.premultiply/1` on the result if you
     still need pre-multiplied output.

  `premultiply/1` and `unpremultiply/1` are only defined for
  `Color.SRGB`, `Color.AdobeRGB` and `Color.RGB` (linear), since
  pre-multiplication is only meaningful in spaces with an RGB tuple.

  """

  @xyz_hub [
    Color.XYZ,
    Color.XYY,
    Color.Lab,
    Color.LCHab,
    Color.Luv,
    Color.LCHuv,
    Color.Oklab,
    Color.Oklch,
    Color.SRGB,
    Color.AdobeRGB,
    Color.Hsl,
    Color.Hsv,
    Color.HSLuv,
    Color.HPLuv,
    Color.CMYK,
    Color.YCbCr,
    Color.JzAzBz,
    Color.ICtCp,
    Color.IPT,
    Color.CAM16UCS
  ]

  # Targets that require a specific reference white. Any source XYZ with
  # a different illuminant is chromatically adapted (Bradford) before
  # being passed to the target's from_xyz/1.
  @fixed_illuminant %{
    Color.SRGB => {:D65, 2},
    Color.AdobeRGB => {:D65, 2},
    Color.Oklab => {:D65, 2},
    Color.Oklch => {:D65, 2},
    Color.Hsl => {:D65, 2},
    Color.Hsv => {:D65, 2},
    Color.HSLuv => {:D65, 2},
    Color.HPLuv => {:D65, 2},
    Color.CMYK => {:D65, 2},
    Color.YCbCr => {:D65, 2},
    Color.JzAzBz => {:D65, 2},
    Color.ICtCp => {:D65, 2},
    Color.IPT => {:D65, 2},
    Color.CAM16UCS => {:D65, 2}
  }

  @doc """
  Builds a color struct from a variety of inputs.

  ### Arguments

  * `input` is one of:

    * A color struct — returned unchanged inside `{:ok, struct}`.

    * A bare list of numbers, interpreted as the color space selected
      by `space` (default `:srgb`). See the "List inputs" section
      below for the detailed rules.

    * A hex string (`"#ff0000"`, `"#ff000080"`, `"#f80"`, or the same
      without the leading `#`).

    * A CSS named color string or atom (`"rebeccapurple"`,
      `:misty_rose`, `"Red"`).

  * `space` is the color space the list is in. One of the short atoms
    (`:srgb`, `:adobe_rgb`, `:cmyk`, `:hsl`, `:hsv`, `:hsluv`,
    `:hpluv`, `:lab`, `:lch` / `:lchab`, `:luv`, `:lchuv`, `:oklab`,
    `:oklch`, `:xyz`, `:xyy`, `:jzazbz`, `:ictcp`, `:ipt`, `:ycbcr`,
    `:cam16_ucs`) or the equivalent module (`Color.SRGB`,
    `Color.Lab`, …). Defaults to `:srgb`. Ignored for non-list
    inputs.

  ### List inputs

  Lists are always either **3** or **4** numbers (4 is a sRGB alpha
  channel, or an HSL/Lab/… alpha channel). `:cmyk` additionally
  accepts **4** or **5** numbers (c, m, y, k, and optionally alpha).

  **Display spaces** (`:srgb`, `:adobe_rgb`, `:cmyk`, `:hsl`, `:hsv`,
  `:hsluv`, `:hpluv`) are **strict**:

  * All elements must be the same numeric type — either **all
    integers** or **all floats**. Mixing is an error.

  * Integer form is **only accepted** for `:srgb`, `:adobe_rgb` and
    `:cmyk`, where each channel is assumed to be in `0..255` and is
    normalised to `[0.0, 1.0]` internally.

  * Each channel is range-checked and a value outside the expected
    range is an error.

  **CIE / perceptual / HDR spaces** (`:lab`, `:lch`, `:luv`,
  `:lchuv`, `:oklab`, `:oklch`, `:xyz`, `:xyy`, `:jzazbz`, `:ictcp`,
  `:ipt`, `:ycbcr`, `:cam16_ucs`) are **permissive**:

  * Floats only — integers are rejected with a clear error.

  * NaN and infinity are rejected.

  * Values outside the nominal range are **not** rejected, because
    wide-gamut and HDR inputs legitimately exceed the "textbook"
    ranges for these spaces.

  For any **cylindrical** space (`:lch`, `:lchuv`, `:oklch`,
  `:hsluv`, `:hpluv`, `:hsl`, `:hsv`), hue values are **normalised**
  into the conventional range (not errored) — `370°` becomes `10°`,
  `-45°` becomes `315°`, and so on.

  ### Returns

  * `{:ok, struct}`.

  * `{:error, reason}` if the input can't be interpreted.

  ### Examples

      iex> {:ok, c} = Color.new([1.0, 0.5, 0.0])
      iex> {c.r, c.g, c.b}
      {1.0, 0.5, 0.0}

      iex> {:ok, c} = Color.new([255, 128, 0])
      iex> {c.r, Float.round(c.g, 4), c.b}
      {1.0, 0.502, 0.0}

      iex> {:ok, c} = Color.new([53.24, 80.09, 67.2], :lab)
      iex> c.illuminant
      :D65

      iex> {:ok, c} = Color.new([0.63, 0.22, 0.13], :oklab)
      iex> c.__struct__
      Color.Oklab

      iex> {:ok, c} = Color.new([0.7, 0.2, 30.0], :oklch)
      iex> c.h
      30.0

      iex> {:ok, c} = Color.new([0.7, 0.2, -45.0], :oklch)
      iex> c.h
      315.0

      iex> {:ok, c} = Color.new([0.0, 0.5, 1.0, 0.0], :cmyk)
      iex> c.c
      0.0

      iex> {:error, %Color.InvalidComponentError{reason: :mixed_types}} = Color.new([1.0, 0, 0])

      iex> {:error, %Color.InvalidComponentError{reason: :out_of_range, range: {0, 255}}} =
      ...>   Color.new([300, 0, 0])

      iex> {:error, %Color.InvalidComponentError{reason: :integers_not_allowed, space: "Lab"}} =
      ...>   Color.new([1, 2, 3], :lab)

  """
  # Maps friendly atoms and module atoms to a canonical short atom.
  @space_aliases %{
    :srgb => :srgb,
    :sRGB => :srgb,
    Color.SRGB => :srgb,
    :adobe_rgb => :adobe_rgb,
    :adobe => :adobe_rgb,
    Color.AdobeRGB => :adobe_rgb,
    :cmyk => :cmyk,
    Color.CMYK => :cmyk,
    :hsl => :hsl,
    Color.Hsl => :hsl,
    :hsv => :hsv,
    Color.Hsv => :hsv,
    :hsluv => :hsluv,
    Color.HSLuv => :hsluv,
    :hpluv => :hpluv,
    Color.HPLuv => :hpluv,
    :lab => :lab,
    Color.Lab => :lab,
    :lch => :lch,
    :lchab => :lch,
    Color.LCHab => :lch,
    :luv => :luv,
    Color.Luv => :luv,
    :lchuv => :lchuv,
    Color.LCHuv => :lchuv,
    :oklab => :oklab,
    Color.Oklab => :oklab,
    :oklch => :oklch,
    Color.Oklch => :oklch,
    :xyz => :xyz,
    Color.XYZ => :xyz,
    :xyy => :xyy,
    :xyY => :xyy,
    Color.XYY => :xyy,
    :jzazbz => :jzazbz,
    Color.JzAzBz => :jzazbz,
    :ictcp => :ictcp,
    Color.ICtCp => :ictcp,
    :ipt => :ipt,
    Color.IPT => :ipt,
    :ycbcr => :ycbcr,
    Color.YCbCr => :ycbcr,
    :cam16 => :cam16_ucs,
    :cam16_ucs => :cam16_ucs,
    Color.CAM16UCS => :cam16_ucs
  }

  def new(input, space \\ :srgb)

  def new([_, _, _] = list, space), do: list_to_color(list, space)
  def new([_, _, _, _] = list, space), do: list_to_color(list, space)
  def new([_, _, _, _, _] = list, space), do: list_to_color(list, space)

  def new(string, _space) when is_binary(string) do
    trimmed = String.trim(string)

    cond do
      # Hex shorthand or full hex — fast path through SRGB.parse.
      String.starts_with?(trimmed, "#") ->
        Color.SRGB.parse(trimmed)

      # Anything that *looks* like a CSS color function call
      # (`rgb(...)`, `hsl(...)`, `lab(...)`, `oklch(...)`,
      # `color(...)`, `device-cmyk(...)`, `color-mix(...)`, etc.)
      # goes through the full CSS Color 5 parser.
      Regex.match?(
        ~r/^(rgba?|hsla?|hwb|lab|lch|oklab|oklch|color|device-cmyk|color-mix)\s*\(/i,
        trimmed
      ) ->
        Color.CSS.parse(trimmed)

      # Named colours and bare hex.
      true ->
        Color.SRGB.parse(trimmed)
    end
  end

  def new(name, _space) when is_atom(name) and name not in [nil, true, false] do
    case Color.CSSNames.lookup(name) do
      {:ok, rgb} -> {:ok, Color.SRGB.unscale255(rgb)}
      {:error, _} = err -> err
    end
  end

  def new(%struct{} = color, _space) do
    if struct in @xyz_hub or struct == Color.RGB do
      {:ok, color}
    else
      {:error,
       %Color.UnsupportedTargetError{target: struct}}
    end
  end

  def new(other, _space) do
    {:error,
     %Color.InvalidColorError{value: other, reason: "input is not a list, string, atom or struct"}}
  end

  defp list_to_color(list, space) do
    case Map.fetch(@space_aliases, space) do
      {:ok, canonical} -> build(canonical, list)
      :error -> {:error, %Color.UnknownColorSpaceError{space: space}}
    end
  end

  # Strict RGB-like
  defp build(:srgb, list), do: strict_rgb(list, Color.SRGB, "sRGB")
  defp build(:adobe_rgb, list), do: strict_rgb(list, Color.AdobeRGB, "Adobe RGB")

  # Strict CMYK — 4 or 5 channels
  defp build(:cmyk, list) when length(list) in [4, 5], do: strict_cmyk(list)
  defp build(:cmyk, list),
    do: {:error, %Color.InvalidComponentError{space: "CMYK", value: list, reason: :wrong_count}}

  # Strict unit-range cylindrical (HSL, HSV — hue in [0, 1])
  defp build(:hsl, list), do: strict_unit_cyl(list, Color.Hsl, "HSL", [:h, :s, :l])
  defp build(:hsv, list), do: strict_unit_cyl(list, Color.Hsv, "HSV", [:h, :s, :v])

  # Strict HSLuv / HPLuv (h in [0, 360), s/l in [0, 100])
  defp build(:hsluv, list), do: strict_deg_percent(list, Color.HSLuv, "HSLuv")
  defp build(:hpluv, list), do: strict_deg_percent(list, Color.HPLuv, "HPLuv")

  # Permissive 3-channel
  defp build(:lab, list),
    do: permissive_3(list, Color.Lab, "Lab", [:l, :a, :b], illuminant: :D65, observer_angle: 2)

  defp build(:luv, list),
    do: permissive_3(list, Color.Luv, "Luv", [:l, :u, :v], illuminant: :D65, observer_angle: 2)

  defp build(:oklab, list),
    do: permissive_3(list, Color.Oklab, "Oklab", [:l, :a, :b], [])

  defp build(:jzazbz, list),
    do: permissive_3(list, Color.JzAzBz, "JzAzBz", [:jz, :az, :bz], [])

  defp build(:ipt, list),
    do: permissive_3(list, Color.IPT, "IPT", [:i, :p, :t], [])

  defp build(:cam16_ucs, list),
    do: permissive_3(list, Color.CAM16UCS, "CAM16-UCS", [:j, :a, :b], [])

  defp build(:xyz, list),
    do: permissive_3(list, Color.XYZ, "XYZ", [:x, :y, :z], illuminant: :D65, observer_angle: 2)

  defp build(:ictcp, list),
    do: permissive_3(list, Color.ICtCp, "ICtCp", [:i, :ct, :cp], transfer: :pq)

  defp build(:ycbcr, list),
    do: permissive_3(list, Color.YCbCr, "YCbCr", [:y, :cb, :cr], variant: :bt709)

  # Permissive cylindrical (hue wraps to [0, 360))
  defp build(:lch, list),
    do: permissive_hue(list, Color.LCHab, "LCHab", [:l, :c, :h], illuminant: :D65, observer_angle: 2)

  defp build(:lchuv, list),
    do: permissive_hue(list, Color.LCHuv, "LCHuv", [:l, :c, :h], illuminant: :D65, observer_angle: 2)

  defp build(:oklch, list),
    do: permissive_hue(list, Color.Oklch, "Oklch", [:l, :c, :h], [])

  # xyY has a non-standard yY field name, so it gets its own builder.
  defp build(:xyy, list) when length(list) in [3, 4] do
    with {:ok, [a1, a2, a3 | rest]} <- permissive_list(list, "xyY") do
      alpha = List.first(rest)
      fields = [x: a1, y: a2, yY: a3, alpha: alpha, illuminant: :D65, observer_angle: 2]
      {:ok, struct!(Color.XYY, fields)}
    end
  end

  defp build(:xyy, list) do
    {:error, %Color.InvalidComponentError{space: "xyY", value: list, reason: :wrong_count}}
  end

  defp build(other, _list) do
    {:error, %Color.UnknownColorSpaceError{space: other}}
  end

  defp strict_rgb(list, module, label) when length(list) in [3, 4] do
    cond do
      Enum.all?(list, &is_integer/1) ->
        with :ok <- check_int_range(list, 0, 255, label) do
          {:ok, struct!(module, rgb_fields(normalise_ints(list, 255)))}
        end

      Enum.all?(list, &is_float/1) ->
        with :ok <- check_float_range(list, 0.0, 1.0, label) do
          {:ok, struct!(module, rgb_fields(list))}
        end

      Enum.all?(list, &is_number/1) ->
        {:error, %Color.InvalidComponentError{space: label, value: list, reason: :mixed_types}}

      true ->
        {:error, %Color.InvalidComponentError{space: label, value: list, reason: :not_numeric}}
    end
  end

  defp strict_rgb(list, _module, label) do
    {:error, %Color.InvalidComponentError{space: label, value: list, reason: :wrong_count}}
  end

  defp strict_cmyk(list) do
    label = "CMYK"

    cond do
      Enum.all?(list, &is_integer/1) ->
        with :ok <- check_int_range(list, 0, 255, label) do
          {:ok, struct!(Color.CMYK, cmyk_fields(normalise_ints(list, 255)))}
        end

      Enum.all?(list, &is_float/1) ->
        with :ok <- check_float_range(list, 0.0, 1.0, label) do
          {:ok, struct!(Color.CMYK, cmyk_fields(list))}
        end

      Enum.all?(list, &is_number/1) ->
        {:error, %Color.InvalidComponentError{space: label, value: list, reason: :mixed_types}}

      true ->
        {:error, %Color.InvalidComponentError{space: label, value: list, reason: :not_numeric}}
    end
  end

  defp strict_unit_cyl(list, module, label, keys) when length(list) in [3, 4] do
    cond do
      Enum.any?(list, &is_integer/1) ->
        {:error,
         %Color.InvalidComponentError{space: label, value: list, reason: :integers_not_allowed}}

      not Enum.all?(list, &is_float/1) ->
        {:error,
         %Color.InvalidComponentError{space: label, value: list, reason: :floats_required}}

      true ->
        [h | rest] = list
        h = wrap_unit(h)
        list2 = [h | rest]

        with :ok <- check_float_range(list2, 0.0, 1.0, label) do
          {:ok, struct!(module, fields(keys, list2))}
        end
    end
  end

  defp strict_unit_cyl(list, _module, label, _) do
    {:error, %Color.InvalidComponentError{space: label, value: list, reason: :wrong_count}}
  end

  defp strict_deg_percent(list, module, label) when length(list) in [3, 4] do
    cond do
      Enum.any?(list, &is_integer/1) ->
        {:error,
         %Color.InvalidComponentError{space: label, value: list, reason: :integers_not_allowed}}

      not Enum.all?(list, &is_float/1) ->
        {:error,
         %Color.InvalidComponentError{space: label, value: list, reason: :floats_required}}

      true ->
        [h | rest] = list
        h = wrap_360(h)
        {sl_pair, alpha_part} = Enum.split(rest, 2)

        with :ok <- check_float_range(sl_pair, 0.0, 100.0, "#{label} S/L"),
             :ok <- check_alpha(alpha_part, label) do
          struct_fields = [h: h] ++ sl_fields(sl_pair) ++ alpha_field(alpha_part)
          {:ok, struct!(module, struct_fields)}
        end
    end
  end

  defp strict_deg_percent(list, _module, label) do
    {:error, %Color.InvalidComponentError{space: label, value: list, reason: :wrong_count}}
  end

  defp permissive_3(list, module, label, [k1, k2, k3], extras) when length(list) in [3, 4] do
    with {:ok, [v1, v2, v3 | rest]} <- permissive_list(list, label) do
      alpha = List.first(rest)
      struct_fields = [{k1, v1}, {k2, v2}, {k3, v3}, {:alpha, alpha}] ++ extras
      {:ok, struct!(module, struct_fields)}
    end
  end

  defp permissive_3(list, _module, label, _, _) do
    {:error, %Color.InvalidComponentError{space: label, value: list, reason: :wrong_count}}
  end

  defp permissive_hue(list, module, label, [k1, k2, k3], extras) when length(list) in [3, 4] do
    with {:ok, [v1, v2, h | rest]} <- permissive_list(list, label) do
      alpha = List.first(rest)
      struct_fields = [{k1, v1}, {k2, v2}, {k3, wrap_360(h)}, {:alpha, alpha}] ++ extras
      {:ok, struct!(module, struct_fields)}
    end
  end

  defp permissive_hue(list, _module, label, _, _) do
    {:error, %Color.InvalidComponentError{space: label, value: list, reason: :wrong_count}}
  end

  defp permissive_list(list, label) do
    cond do
      Enum.any?(list, &is_integer/1) ->
        {:error,
         %Color.InvalidComponentError{space: label, value: list, reason: :integers_not_allowed}}

      not Enum.all?(list, &is_float/1) ->
        {:error,
         %Color.InvalidComponentError{space: label, value: list, reason: :floats_required}}

      Enum.any?(list, &(&1 != &1)) ->
        {:error, %Color.InvalidComponentError{space: label, value: list, reason: :nan}}

      Enum.any?(list, fn f -> f == :infinity or f == :neg_infinity end) ->
        {:error, %Color.InvalidComponentError{space: label, value: list, reason: :infinity}}

      true ->
        {:ok, list}
    end
  end

  defp rgb_fields([r, g, b]), do: [r: r, g: g, b: b]
  defp rgb_fields([r, g, b, a]), do: [r: r, g: g, b: b, alpha: a]

  defp cmyk_fields([c, m, y, k]), do: [c: c, m: m, y: y, k: k]
  defp cmyk_fields([c, m, y, k, a]), do: [c: c, m: m, y: y, k: k, alpha: a]

  defp fields([k1, k2, k3], [v1, v2, v3]), do: [{k1, v1}, {k2, v2}, {k3, v3}]
  defp fields([k1, k2, k3], [v1, v2, v3, a]),
    do: [{k1, v1}, {k2, v2}, {k3, v3}, {:alpha, a}]

  defp sl_fields([s, l]), do: [s: s, l: l]

  defp normalise_ints(list, max), do: Enum.map(list, fn n -> n / max end)

  defp check_int_range(list, lo, hi, label) do
    if Enum.all?(list, fn n -> n >= lo and n <= hi end) do
      :ok
    else
      {:error,
       %Color.InvalidComponentError{
         space: label,
         value: list,
         range: {lo, hi},
         reason: :out_of_range
       }}
    end
  end

  defp check_float_range(list, lo, hi, label) do
    if Enum.all?(list, fn n -> n >= lo and n <= hi end) do
      :ok
    else
      {:error,
       %Color.InvalidComponentError{
         space: label,
         value: list,
         range: {lo, hi},
         reason: :out_of_range
       }}
    end
  end

  defp check_alpha([], _label), do: :ok
  defp check_alpha([a], label), do: check_float_range([a], 0.0, 1.0, "#{label} alpha")

  defp alpha_field([]), do: []
  defp alpha_field([a]), do: [alpha: a]

  defp wrap_unit(h) do
    r = :math.fmod(h, 1.0)
    if r < 0, do: r + 1.0, else: r
  end

  defp wrap_360(h) do
    r = :math.fmod(h, 360)
    if r < 0, do: r + 360, else: r
  end

  @doc """
  Converts a color to a different color space.

  `color` may be anything accepted by `new/1`, including a bare list
  `[r, g, b]` or `[r, g, b, a]` (interpreted as sRGB), a hex string, a
  CSS named color, or a color struct.

  For `Color.RGB` (linear, any working space) use `convert/3` and pass
  the working-space atom as the third argument.

  ### Arguments

  * `color` is any input accepted by `new/1`.

  * `target` is the target module (for example `Color.Lab`, `Color.SRGB`).

  * `options` is a keyword list — see below.

  ### Options

  * `:intent` — the ICC rendering intent. One of:

    * `:relative_colorimetric` (default) — chromatically adapt the
      source white to the target white using Bradford. Out-of-gamut
      colors are **not** altered; any clipping is left to the caller
      or deferred to a later step. This matches the current
      default behaviour.

    * `:absolute_colorimetric` — **no** chromatic adaptation. The
      source XYZ is handed to the target's `from_xyz/1` verbatim.
      Use this when you want to preserve the exact XYZ values
      regardless of reference-white mismatch.

    * `:perceptual` — chromatically adapt **and** gamut-map so the
      result is inside the target's gamut (when the target has a
      gamut, i.e. an RGB working space). The gamut-mapping algorithm
      is CSS Color 4's Oklch binary search (same as
      `Color.Gamut.to_gamut/3` with `method: :oklch`).

    * `:saturation` — currently an alias for `:perceptual`. Treated
      as a gamut-compressing intent. (A true "saturation" intent
      that preserves chroma at the cost of hue shift is deferred to
      a future version.)

  * `:bpc` — `true` to apply black point compensation after chromatic
    adaptation, `false` (default) to skip it. See
    `Color.XYZ.apply_bpc/3`.

  * `:adaptation` — the chromatic adaptation method used by
    `:relative_colorimetric` and `:perceptual`. One of `:bradford`
    (default), `:xyz_scaling`, `:von_kries`, `:sharp`, `:cmccat2000`,
    `:cat02`.

  ### Returns

  * `{:ok, %target{}}` on success.

  * `{:error, reason}` if the conversion can't be performed.

  ### Examples

      iex> {:ok, lab} = Color.convert(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0}, Color.Lab)
      iex> {Float.round(lab.l, 2), Float.round(lab.a, 2), Float.round(lab.b, 2)}
      {53.24, 80.09, 67.2}

      iex> {:ok, lab} = Color.convert([1.0, 0.0, 0.0], Color.Lab)
      iex> Float.round(lab.l, 2)
      53.24

      iex> {:ok, srgb} = Color.convert("#ff0000", Color.SRGB)
      iex> {Float.round(srgb.r, 6), Float.round(srgb.g, 6), Float.round(srgb.b, 6)}
      {1.0, 0.0, 0.0}

      iex> {:ok, srgb} = Color.convert(%Color.Lab{l: 53.2408, a: 80.0925, b: 67.2032}, Color.SRGB)
      iex> {Float.round(srgb.r, 3), Float.round(srgb.g, 3), Float.round(srgb.b, 3)}
      {1.0, 0.0, 0.0}

      iex> {:ok, c} = Color.convert([1.0, 0.0, 0.0, 0.5], Color.Lab)
      iex> c.alpha
      0.5

  Wide-gamut Display P3 red gamut-mapped into sRGB via the
  `:perceptual` intent:

      iex> p3_red = %Color.RGB{r: 1.0, g: 0.0, b: 0.0, working_space: :P3_D65}
      iex> {:ok, mapped} = Color.convert(p3_red, Color.SRGB, intent: :perceptual)
      iex> Color.Gamut.in_gamut?(mapped, :SRGB)
      true

  """
  def convert(color, target), do: do_convert(color, target, nil, [])

  def convert(color, Color.RGB, working_space) when is_atom(working_space),
    do: do_convert(color, Color.RGB, working_space, [])

  def convert(color, target, options) when is_list(options),
    do: do_convert(color, target, nil, options)

  @doc """
  Converts a color to `Color.RGB` (linear) in the given working space
  with rendering-intent options.

  ### Arguments

  * `color` is any supported color struct or input accepted by `new/1`.

  * `target` must be `Color.RGB`.

  * `working_space` is an atom naming an RGB working space (for
    example `:SRGB`, `:Adobe`, `:ProPhoto`).

  * `options` is the same keyword list as `convert/3`, supporting
    `:intent`, `:bpc`, and `:adaptation`.

  ### Returns

  * `{:ok, %Color.RGB{}}` on success.

  ### Examples

      iex> {:ok, rgb} = Color.convert(%Color.SRGB{r: 1.0, g: 1.0, b: 1.0}, Color.RGB, :SRGB)
      iex> {Float.round(rgb.r, 3), Float.round(rgb.g, 3), Float.round(rgb.b, 3)}
      {1.0, 1.0, 1.0}

  """
  def convert(color, Color.RGB, working_space, options)
      when is_atom(working_space) and is_list(options) do
    do_convert(color, Color.RGB, working_space, options)
  end

  defp do_convert(_color, Color.RGB, nil, _options) do
    {:error, %Color.MissingWorkingSpaceError{}}
  end

  defp do_convert(color, Color.RGB, working_space, options) do
    intent = Keyword.get(options, :intent, :relative_colorimetric)
    bpc = Keyword.get(options, :bpc, false)
    method = Keyword.get(options, :adaptation, :bradford)

    with {:ok, info} <- Color.RGB.WorkingSpace.rgb_conversion_matrix(working_space),
         {:ok, color} <- new(color),
         {:ok, xyz} <- to_xyz(color),
         {:ok, xyz} <-
           adapt_xyz(xyz, info.illuminant, info.observer_angle, intent, method, bpc),
         {:ok, converted} <- Color.RGB.from_xyz(xyz, working_space) do
      apply_intent_gamut_rgb(converted, intent, working_space)
    end
  end

  defp do_convert(color, target, _, options) when target in @xyz_hub do
    intent = Keyword.get(options, :intent, :relative_colorimetric)
    bpc = Keyword.get(options, :bpc, false)
    method = Keyword.get(options, :adaptation, :bradford)

    with {:ok, color} <- new(color),
         {:ok, xyz} <- to_xyz(color),
         {:ok, xyz} <- adapt_for(xyz, target, intent, method, bpc),
         {:ok, converted} <- target.from_xyz(xyz) do
      apply_intent_gamut(converted, intent, target)
    end
  end

  defp do_convert(_color, target, _, _options) do
    {:error, %Color.UnsupportedTargetError{target: target}}
  end

  # Called from convert/3 for non-RGB targets.
  defp adapt_for(%Color.XYZ{} = xyz, target, intent, method, bpc) do
    case {intent, Map.get(@fixed_illuminant, target)} do
      {:absolute_colorimetric, _} ->
        {:ok, xyz}

      {_, nil} ->
        {:ok, xyz}

      {_, {illuminant, observer}} ->
        adapt_xyz(xyz, illuminant, observer, intent, method, bpc)
    end
  end

  defp adapt_xyz(xyz, dest_illuminant, dest_observer, intent, method, bpc) do
    case intent do
      :absolute_colorimetric ->
        {:ok, xyz}

      _ ->
        with {:ok, adapted} <-
               Color.XYZ.adapt(xyz, dest_illuminant,
                 observer_angle: dest_observer,
                 method: method
               ) do
          if bpc do
            {:ok, Color.XYZ.apply_bpc(adapted, 0.0, 0.0)}
          else
            {:ok, adapted}
          end
        end
    end
  end

  # For non-RGB targets: perceptual / saturation intents gamut-map
  # into sRGB as the de-facto display gamut.
  defp apply_intent_gamut(converted, intent, _target)
       when intent in [:relative_colorimetric, :absolute_colorimetric] do
    {:ok, converted}
  end

  defp apply_intent_gamut(converted, intent, target)
       when intent in [:perceptual, :saturation] do
    # For RGB-like targets we gamut-map directly into that target's
    # working space. For perceptual spaces (Lab, Oklch, etc.) we
    # leave the value unchanged — those spaces have no gamut.
    case target do
      Color.SRGB -> to_gamut_srgb(converted, :SRGB)
      Color.AdobeRGB -> to_gamut_srgb(converted, :Adobe)
      _ -> {:ok, converted}
    end
  end

  defp apply_intent_gamut_rgb(rgb, intent, _working_space)
       when intent in [:relative_colorimetric, :absolute_colorimetric] do
    {:ok, rgb}
  end

  defp apply_intent_gamut_rgb(rgb, intent, working_space)
       when intent in [:perceptual, :saturation] do
    Color.Gamut.to_gamut(rgb, working_space, method: :oklch)
  end

  defp to_gamut_srgb(converted, working_space) do
    Color.Gamut.to_gamut(converted, working_space, method: :oklch)
  end

  @doc """
  Converts any supported color to `Color.XYZ`.

  ### Arguments

  * `color` is any supported color struct.

  ### Returns

  * `{:ok, %Color.XYZ{}}`.

  """
  def to_xyz(%Color.XYZ{} = xyz), do: {:ok, xyz}
  def to_xyz(%Color.XYY{} = c), do: Color.XYY.to_xyz(c)
  def to_xyz(%Color.Lab{} = c), do: Color.Lab.to_xyz(c)
  def to_xyz(%Color.LCHab{} = c), do: Color.LCHab.to_xyz(c)
  def to_xyz(%Color.Luv{} = c), do: Color.Luv.to_xyz(c)
  def to_xyz(%Color.LCHuv{} = c), do: Color.LCHuv.to_xyz(c)
  def to_xyz(%Color.Oklab{} = c), do: Color.Oklab.to_xyz(c)
  def to_xyz(%Color.Oklch{} = c), do: Color.Oklch.to_xyz(c)
  def to_xyz(%Color.HSLuv{} = c), do: Color.HSLuv.to_xyz(c)
  def to_xyz(%Color.HPLuv{} = c), do: Color.HPLuv.to_xyz(c)
  def to_xyz(%Color.CMYK{} = c), do: Color.CMYK.to_xyz(c)
  def to_xyz(%Color.YCbCr{} = c), do: Color.YCbCr.to_xyz(c)
  def to_xyz(%Color.JzAzBz{} = c), do: Color.JzAzBz.to_xyz(c)
  def to_xyz(%Color.ICtCp{} = c), do: Color.ICtCp.to_xyz(c)
  def to_xyz(%Color.IPT{} = c), do: Color.IPT.to_xyz(c)
  def to_xyz(%Color.CAM16UCS{} = c), do: Color.CAM16UCS.to_xyz(c)
  def to_xyz(%Color.SRGB{} = c), do: Color.SRGB.to_xyz(c)
  def to_xyz(%Color.AdobeRGB{} = c), do: Color.AdobeRGB.to_xyz(c)
  def to_xyz(%Color.RGB{} = c), do: Color.RGB.to_xyz(c)
  def to_xyz(%Color.Hsl{} = c), do: Color.Hsl.to_xyz(c)
  def to_xyz(%Color.Hsv{} = c), do: Color.Hsv.to_xyz(c)

  @doc """
  Pre-multiplies a color's channels by its alpha.

  Only supported for RGB-tuple color spaces (`Color.SRGB`,
  `Color.AdobeRGB`, `Color.RGB`) since pre-multiplication is not
  meaningful for opponent or cylindrical spaces. A color with `nil`
  alpha is treated as fully opaque (`alpha = 1.0`) and is returned
  unchanged.

  ### Arguments

  * `color` is an RGB-tuple color struct.

  ### Returns

  * A new color struct of the same type with pre-multiplied channels.

  ### Examples

      iex> Color.premultiply(%Color.SRGB{r: 1.0, g: 0.5, b: 0.25, alpha: 0.5})
      %Color.SRGB{r: 0.5, g: 0.25, b: 0.125, alpha: 0.5}

      iex> Color.premultiply(%Color.SRGB{r: 1.0, g: 0.5, b: 0.25})
      %Color.SRGB{r: 1.0, g: 0.5, b: 0.25, alpha: nil}

  """
  def premultiply(%Color.SRGB{alpha: nil} = c), do: c
  def premultiply(%Color.SRGB{alpha: a} = c), do: %{c | r: c.r * a, g: c.g * a, b: c.b * a}

  def premultiply(%Color.AdobeRGB{alpha: nil} = c), do: c
  def premultiply(%Color.AdobeRGB{alpha: a} = c), do: %{c | r: c.r * a, g: c.g * a, b: c.b * a}

  def premultiply(%Color.RGB{alpha: nil} = c), do: c
  def premultiply(%Color.RGB{alpha: a} = c), do: %{c | r: c.r * a, g: c.g * a, b: c.b * a}

  def premultiply(%struct{}) do
    raise ArgumentError,
          "premultiply/1 is only supported for Color.SRGB, Color.AdobeRGB and " <>
            "Color.RGB (linear). Got #{inspect(struct)}."
  end

  @doc """
  Inverts `premultiply/1`. A color with `nil` alpha is returned
  unchanged; a color with `alpha = 0.0` is returned unchanged (the
  original channels are unrecoverable and the alpha is authoritative).

  ### Arguments

  * `color` is an RGB-tuple color struct.

  ### Returns

  * A new color struct of the same type with un-pre-multiplied channels.

  ### Examples

      iex> Color.unpremultiply(%Color.SRGB{r: 0.5, g: 0.25, b: 0.125, alpha: 0.5})
      %Color.SRGB{r: 1.0, g: 0.5, b: 0.25, alpha: 0.5}

      iex> Color.unpremultiply(%Color.SRGB{r: 0.0, g: 0.0, b: 0.0, alpha: 0.0})
      %Color.SRGB{r: 0.0, g: 0.0, b: 0.0, alpha: 0.0}

  """
  def unpremultiply(%Color.SRGB{alpha: nil} = c), do: c
  def unpremultiply(%Color.SRGB{alpha: a} = c) when a == 0, do: c
  def unpremultiply(%Color.SRGB{alpha: a} = c), do: %{c | r: c.r / a, g: c.g / a, b: c.b / a}

  def unpremultiply(%Color.AdobeRGB{alpha: nil} = c), do: c
  def unpremultiply(%Color.AdobeRGB{alpha: a} = c) when a == 0, do: c
  def unpremultiply(%Color.AdobeRGB{alpha: a} = c),
    do: %{c | r: c.r / a, g: c.g / a, b: c.b / a}

  def unpremultiply(%Color.RGB{alpha: nil} = c), do: c
  def unpremultiply(%Color.RGB{alpha: a} = c) when a == 0, do: c
  def unpremultiply(%Color.RGB{alpha: a} = c), do: %{c | r: c.r / a, g: c.g / a, b: c.b / a}

  def unpremultiply(%struct{}) do
    raise ArgumentError,
          "unpremultiply/1 is only supported for Color.SRGB, Color.AdobeRGB and " <>
            "Color.RGB (linear). Got #{inspect(struct)}."
  end

  @doc """
  Returns the WCAG 2.x relative luminance of a color — the CIE `Y`
  component of its linear sRGB, on the `[0, 1]` scale.

  This is a convenience delegate to
  `Color.Contrast.relative_luminance/1`, exposed at the top level for
  discoverability since it's used all over the place (perceptual
  sort, accessibility checks, threshold-based luminance picking,
  HDR tone mapping, etc.).

  ### Arguments

  * `color` is anything accepted by `new/1`.

  ### Returns

  * A float in `[0, 1]`.

  ### Examples

      iex> Color.luminance("white")
      1.0

      iex> Color.luminance("black")
      0.0

      iex> Float.round(Color.luminance("red"), 4)
      0.2126

  """
  defdelegate luminance(color), to: Color.Contrast, as: :relative_luminance

  @doc """
  Sorts a list of colors by a perceptual criterion.

  ### Arguments

  * `colors` is a list of anything accepted by `new/1`.

  * `options` is a keyword list.

  ### Options

  * `:by` selects the sort key. One of:

    * `:luminance` — WCAG relative luminance (default, dark → light).

    * `:lightness` — CIE Lab `L*` (dark → light).

    * `:oklab_l` — Oklab `L` (dark → light).

    * `:chroma` — CIELCh `C*` (grey → saturated).

    * `:oklch_c` — Oklch `C` (grey → saturated).

    * `:hue` — CIELCh hue in degrees (red → red, around the wheel).

    * `:oklch_h` — Oklch hue in degrees.

    * `:hlv` — the HLV hue/luminance/value bucketing from
      https://www.alanzucconi.com/2015/09/30/colour-sorting/ (good
      for palette display).

    * A 1-arity function that maps a color struct to a comparable
      sort key.

  * `:order` — `:asc` (default) or `:desc`.

  ### Returns

  * `{:ok, sorted_colors}` with each element as a `Color.SRGB` struct.

  * `{:error, reason}` if any input can't be parsed.

  ### Examples

      iex> {:ok, sorted} = Color.sort(["white", "black", "#888"], by: :luminance)
      iex> Enum.map(sorted, &Color.SRGB.to_hex/1)
      ["#000000", "#888888", "#ffffff"]

      iex> {:ok, sorted} = Color.sort(["red", "green", "blue"], by: :hue)
      iex> Enum.map(sorted, &Color.SRGB.to_hex/1) |> length()
      3

  """
  def sort(colors, options \\ []) when is_list(colors) do
    by = Keyword.get(options, :by, :luminance)
    order = Keyword.get(options, :order, :asc)

    with {:ok, srgbs} <- normalise_sort_inputs(colors) do
      key = sort_key(by)
      sorter = if order == :desc, do: :desc, else: :asc
      {:ok, Enum.sort_by(srgbs, key, sorter)}
    end
  end

  defp normalise_sort_inputs(colors) do
    Enum.reduce_while(colors, {:ok, []}, fn c, {:ok, acc} ->
      case convert(c, Color.SRGB) do
        {:ok, srgb} -> {:cont, {:ok, [srgb | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp sort_key(fun) when is_function(fun, 1), do: fun
  defp sort_key(:luminance), do: &Color.Contrast.relative_luminance/1

  defp sort_key(:lightness) do
    fn c ->
      {:ok, lab} = convert(c, Color.Lab)
      lab.l
    end
  end

  defp sort_key(:oklab_l) do
    fn c ->
      {:ok, ok} = convert(c, Color.Oklab)
      ok.l
    end
  end

  defp sort_key(:chroma) do
    fn c ->
      {:ok, lch} = convert(c, Color.LCHab)
      lch.c
    end
  end

  defp sort_key(:oklch_c) do
    fn c ->
      {:ok, oklch} = convert(c, Color.Oklch)
      oklch.c
    end
  end

  defp sort_key(:hue) do
    fn c ->
      {:ok, lch} = convert(c, Color.LCHab)
      lch.h
    end
  end

  defp sort_key(:oklch_h) do
    fn c ->
      {:ok, oklch} = convert(c, Color.Oklch)
      oklch.h
    end
  end

  # Zucconi's HLV bucket sort — rounds hue/lightness/value into coarse
  # buckets so colors cluster into visually-related groups.
  defp sort_key(:hlv) do
    fn c ->
      reps = 8

      {:ok, hsv} = convert(c, Color.Hsv)
      lum = :math.sqrt(0.241 * c.r + 0.691 * c.g + 0.068 * c.b)
      h2 = trunc(hsv.h * reps)
      lum2 = trunc(lum * reps)
      v2 = trunc(hsv.v * reps)

      # Reverse the value within odd hue buckets so the sort
      # alternates direction — this is the trick that turns the
      # sequence into a pleasing perceptual gradient.
      lum2 = if rem(h2, 2) == 1, do: reps - lum2, else: lum2
      v2 = if rem(h2, 2) == 1, do: reps - v2, else: v2
      {h2, lum2, v2}
    end
  end

  defp sort_key(other) do
    raise ArgumentError,
          "Unknown sort key #{inspect(other)}. Valid keys: :luminance, " <>
            ":lightness, :oklab_l, :chroma, :oklch_c, :hue, :oklch_h, :hlv, " <>
            "or a 1-arity function."
  end
end
