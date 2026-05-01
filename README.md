# Color

[![Hex.pm](https://img.shields.io/hexpm/v/color.svg)](https://hex.pm/packages/color)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/color)
[![CI](https://github.com/elixir-image/color/actions/workflows/ci.yml/badge.svg)](https://github.com/elixir-image/color/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/color.svg)](https://github.com/elixir-image/color/blob/main/LICENSE.md)

A comprehensive Elixir library for representing, converting, and analysing color, with no runtime dependencies.

`Color` covers the CIE color spaces, the modern perceptual spaces (Oklab, JzAzBz, ICtCp, IPT, CAM16-UCS), the standard RGB working spaces (sRGB, Adobe RGB, Display P3, Rec. 709, Rec. 2020, ProPhoto, …), the non-linear UI spaces (HSL, HSV, HSLuv, HPLuv), CMYK, YCbCr (BT.601 / 709 / 2020) and the spectral pipeline (CIE 1931 and 1964 standard observers, illuminants, reflectance integration). Conversions are based on the canonical formulas published by [Bruce Lindbloom](http://www.brucelindbloom.com/).

Beyond conversions, the library provides chromatic adaptation (Bradford, von Kries, CAT02, …), four ΔE color-difference metrics (CIE76, CIE94, CIEDE2000, CMC l:c), WCAG and APCA contrast, gamut checking and CSS Color 4 perceptual gamut mapping, color mixing and gradient generation, harmonies, color temperature, blend modes, CSS Color 4 / 5 parsing and serialisation, an ICC matrix-profile reader, and a `~COLOR` sigil.

## Features

* **20+ color space structs** including `Color.SRGB`, `Color.AdobeRGB`, `Color.RGB` (linear, in any of 24 named working spaces), `Color.Lab`, `Color.LCHab`, `Color.Luv`, `Color.LCHuv`, `Color.XYZ`, `Color.XyY`, `Color.Oklab`, `Color.Oklch`, `Color.HSLuv`, `Color.HPLuv`, `Color.HSL`, `Color.HSV`, `Color.CMYK`, `Color.YCbCr`, `Color.JzAzBz`, `Color.ICtCp`, `Color.IPT`, `Color.CAM16UCS`.

* **Top-level conversion API**. `Color.new/2` and `Color.convert/2,3,4` accept structs, hex strings, CSS named colors, atoms, or bare lists of numbers (with strict per-space validation) and convert between any pair of supported spaces. `Color.convert_many/2,3,4` is the batch equivalent. Alpha is preserved across every path.

* **Chromatic adaptation** with six methods (`:bradford`, `:xyz_scaling`, `:von_kries`, `:sharp`, `:cmccat2000`, `:cat02`). `Color.convert/3,4` auto-adapts the source illuminant when the target requires a fixed reference white.

* **ICC rendering intents** wired into `Color.convert/3,4`: `:relative_colorimetric` (default), `:absolute_colorimetric`, `:perceptual`, `:saturation`. Optional black-point compensation via `bpc: true`.

* **ICC matrix-profile reader** (`Color.ICC.Profile`) for ICC v2 / v4 RGB→XYZ profiles, with `curv` LUT and `para` parametric tone response curves. Loads profiles like `sRGB IEC61966-2.1.icc`, `Display P3.icc`, `AdobeRGB1998.icc`, and most camera and scanner profiles.

* **Color difference (ΔE)**. CIE76, CIE94, CIEDE2000 (verified against the Sharma 2005 test data), and CMC l:c.

* **Contrast**. WCAG 2.x relative luminance and contrast ratio, APCA W3 0.1.9 (`L_c`), and `pick_contrasting/2` for accessibility helpers.

* **Mixing and gradients**. `Color.Mix.mix/4` interpolates in any supported space (default Oklab) with CSS Color 4 hue-interpolation modes (`:shorter`, `:longer`, `:increasing`, `:decreasing`). `Color.Mix.gradient/4` produces evenly spaced gradients.

* **Gamut checking and mapping**. `Color.Gamut.in_gamut?/2` and `Color.Gamut.to_gamut/3` with the CSS Color 4 Oklch binary-search algorithm or simple RGB clip.

* **Color harmonies**. Complementary, analogous, triadic, tetradic, and split-complementary in any cylindrical space (default Oklch).

* **Palette generation**. `Color.Palette.tonal/2` produces Tailwind / Radix style tonal scales in Oklch. `Color.Palette.theme/2` produces Material Design 3 style themes — five coordinated scales from one seed, with Material role tokens. `Color.Palette.contrast/2` produces Adobe Leonardo style contrast-targeted palettes that hit exact WCAG or APCA ratios against a chosen background. `Color.Palette.contrast_scale/2` produces contrast-constrained tonal scales (Ström-Awn style) where any two stops ≥ `apart` label units apart are guaranteed to satisfy a minimum contrast ratio by construction.

* **Palette transforms**. `Color.Palette.sort/2` orders an arbitrary list of colours into a perceptually-sensible sequence (rainbow, stepped-hue grid, lightness ramp, or material-aware PBR order with `%Color.Material{}` finishes). `Color.Palette.summarize/3` reduces a list of N colours to at most K representatives by agglomerative clustering in Oklab, with mass weighting and centroid-aware swatch selection. `Color.Palette.Cluster` exposes the underlying `merge_until/3`, `merge_pair/2`, `representative/2`, and `distance/3` primitives so libraries that produce their own clusters (e.g. K-means over image pixels in [`:image`](https://hex.pm/packages/image)) can re-use the same algorithm.

* **Color temperature**. CCT ↔ chromaticity, Planckian locus and CIE daylight locus.

* **CSS Color Module Level 4 / 5**. Full parser and serialiser for hex, named colors, `rgb()/rgba()`, `hsl()/hsla()`, `hwb()`, `lab()`, `lch()`, `oklab()`, `oklch()`, `color(srgb|display-p3|rec2020|…)`, `device-cmyk()`, `color-mix()`, relative color syntax, `none` keyword, and `calc()` expressions.

* **`~COLOR` sigil** for compile-time color literals in any supported space.

* **Spectral pipeline**. `Color.Spectral` and `Color.Spectral.Tables` provide the CIE 1931 2° and CIE 1964 10° standard observer CMFs, the D65 / D50 / A / E illuminant SPDs, emissive and reflective integration to XYZ, and a metamerism helper.

* **Blend modes**. All 16 CSS Compositing Level 1 modes (`:multiply`, `:screen`, `:overlay`, `:darken`, `:lighten`, `:color_dodge`, `:color_burn`, `:hard_light`, `:soft_light`, `:difference`, `:exclusion`, `:hue`, `:saturation`, `:color`, `:luminosity`, `:normal`).

* **Transfer functions**. sRGB, gamma 2.2 / 1.8, L*, BT.709, BT.2020, PQ (SMPTE ST 2084), HLG, Adobe RGB γ.

* **Pre-multiplied alpha helpers**. `Color.premultiply/1` and `Color.unpremultiply/1` for callers that need to round-trip pre-multiplied pixel data through the conversion pipeline.

* **Typed errors**. Every fallible function returns `{:ok, color}` or `{:error, %SomeError{...}}` where the exception struct carries the offending value, the space, the reason, and any other relevant fields. See `Color.InvalidColorError`, `Color.InvalidComponentError`, `Color.UnknownColorSpaceError`, `Color.UnknownColorNameError`, `Color.UnknownWorkingSpaceError`, `Color.InvalidHexError`, `Color.ParseError`, `Color.UnknownBlendModeError`, `Color.UnknownGamutMethodError`, `Color.MissingWorkingSpaceError`, `Color.UnsupportedTargetError`, `Color.ICC.ParseError`.

## Supported Elixir and OTP Releases

`Color` is supported on Elixir 1.17+ and OTP 26+.

## Quick Start

Add `:color` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:color, "~> 0.1.0"}
  ]
end
```

Then run `mix deps.get`.

### Building colors

```elixir
# From a hex string or CSS named color:
{:ok, red}    = Color.new("#ff0000")
{:ok, purple} = Color.new("rebeccapurple")
{:ok, also}   = Color.new(:misty_rose)

# From a list of unit-range floats (assumed sRGB):
{:ok, srgb}   = Color.new([1.0, 0.5, 0.0])

# From a list of 0..255 integers (assumed sRGB):
{:ok, srgb}   = Color.new([255, 128, 0])

# In any supported space:
{:ok, lab}    = Color.new([53.24, 80.09, 67.20], :lab)
{:ok, oklch}  = Color.new([0.7, 0.2, 30.0], :oklch)
{:ok, cmyk}   = Color.new([0.0, 0.5, 1.0, 0.0], :cmyk)
```

### Converting

```elixir
{:ok, lab}     = Color.convert("#ff0000", Color.Lab)
{:ok, oklch}   = Color.convert([1.0, 0.0, 0.0], Color.Oklch)
{:ok, cmyk}    = Color.convert(:rebecca_purple, Color.CMYK)
{:ok, p3}      = Color.convert(red, Color.RGB, :P3_D65)

# Wide-gamut Display P3 colors gamut-mapped into sRGB
# using the CSS Color 4 Oklch perceptual algorithm:
{:ok, mapped}  = Color.convert(p3, Color.SRGB, intent: :perceptual)

# Batch convert a list:
{:ok, labs}    = Color.convert_many(["red", "green", "blue"], Color.Lab)
```

### Difference and contrast

```elixir
Color.Distance.delta_e_2000(red, purple)        # CIEDE2000
Color.Contrast.wcag_ratio("white", "#777")      # 4.48
Color.Contrast.wcag_level("black", "white")     # :aaa
Color.Contrast.apca("black", "white")           # 106.04
```

### Mixing, gradients, harmonies

```elixir
{:ok, mid}    = Color.Mix.mix("red", "blue", 0.5, in: Color.Oklch)
{:ok, ramp}   = Color.Mix.gradient("black", "white", 8)
{:ok, [_a, _b]}    = Color.Harmony.complementary("red")
{:ok, [_a, _b, _c]} = Color.Harmony.triadic("red")
```

### Palettes

See the [palette guide](https://hexdocs.pm/color/palettes.html) for background, research, and when to use each algorithm, the [visualizer guide](https://hexdocs.pm/color/visualizer.html) for the optional Plug-based web preview (`Color.Palette.Visualizer`), and the [integrations guide](https://hexdocs.pm/color/integrations.html) for building design-system tooling on top of `Color.Palette.Tonal.to_css/2` / `to_tailwind/2` / `to_tokens/2` and `Color.Gamut.SVG.render/1`.

Generate design-system palettes from a single seed colour:

```elixir
# Tailwind / Radix style tonal scale
scale = Color.Palette.tonal("#3b82f6", name: "blue")
Map.fetch!(scale.stops, 500) |> Color.to_hex()  # => seed (snapped)

# Material Design 3 style theme — five coordinated scales from one seed
theme = Color.Palette.theme("#3b82f6")
{:ok, primary}      = Color.Palette.Theme.role(theme, :primary)
{:ok, on_primary}   = Color.Palette.Theme.role(theme, :on_primary)
{:ok, surface_dark} = Color.Palette.Theme.role(theme, :surface, scheme: :dark)

# Adobe Leonardo style contrast-targeted palette
accessible = Color.Palette.contrast("#3b82f6",
  background: "white",
  targets: [3.0, 4.5, 7.0]   # WCAG AA large, AA, AAA
)

# Contrast-constrained tonal scale (Ström-Awn style) — any two stops
# ≥ 500 apart are guaranteed to contrast ≥ 4.5:1 against each other
guaranteed = Color.Palette.contrast_scale("#3b82f6",
  guarantee: {4.5, 500}
)

# Sort a heterogeneous bag of colours into rainbow order in Oklch.
Color.Palette.sort(["#808080", "#0000ff", "#ff0000", "#00ff00"])
# => sorted: gray, red, green, blue

# Reduce N colours to K representatives by agglomerative clustering
# in Oklab (perceptually uniform, chromatic-axis weighted 2× over L).
Color.Palette.summarize(
  ["#ff0000", "#fe0202", "#0000ff", "#0202fe", "#00ff00"],
  3
)
# => 3 SRGB swatches, one per surviving cluster
```

### CSS Color 4 / 5

```elixir
{:ok, c} = Color.CSS.parse("oklch(70% 0.15 180 / 50%)")
Color.CSS.to_css(c)
# => "oklch(70% 0.15 180 / 0.5)"

{:ok, c} = Color.CSS.parse("color-mix(in oklch, red 30%, blue)")
{:ok, c} = Color.CSS.parse("rgb(from oklch(0.7 0.15 180) calc(r * 0.9) g b)")
```

### ~COLOR Sigil

```elixir
import Color.Sigil

~COLOR[#ff0000]            # Color.SRGB
~COLOR[rebeccapurple]      # Color.SRGB via CSS name
~COLOR[1.0, 0.5, 0.0]r     # unit sRGB
~COLOR[255, 128, 0]b       # 0..255 sRGB
~COLOR[53.24, 80.09, 67.2]l   # Color.Lab
~COLOR[0.63, 0.22, 0.13]o     # Color.Oklab
```

### Spectral

```elixir
d65 = Color.Spectral.illuminant(:D65)
{:ok, white_xyz} = Color.Spectral.to_xyz(d65)
# => Color.XYZ at D65 white point

# Reflectance under an illuminant:
sample = %Color.Spectral{wavelengths: ws, values: rs}
{:ok, xyz} = Color.Spectral.reflectance_to_xyz(sample, :D65)

# Detect a metamer pair:
{:ok, delta_e} = Color.Spectral.metamerism(sample_a, sample_b, :D65, :A)
```

### ICC profiles

```elixir
{:ok, profile} = Color.ICC.Profile.load("/path/to/Display P3.icc")
profile.description
# => "Display P3"

{x, y, z} = Color.ICC.Profile.to_xyz(profile, {1.0, 0.0, 0.0})
# => XYZ in PCS (D50, 2°)

{r, g, b} = Color.ICC.Profile.from_xyz(profile, {0.9642, 1.0, 0.8249})
# => encoded RGB in the profile's colour space
```

## Documentation

See the module documentation on [HexDocs](https://hexdocs.pm/color).

## Contributing

A `mix format` pre-commit hook is committed under `.githooks/`. Enable it once per clone with:

```sh
git config core.hooksPath .githooks
```

The hook formats every staged `.ex` / `.exs` file with `mix format` and re-stages the result, so commits never include unformatted code.

## License

Apache 2.0. See [LICENSE.md](LICENSE.md) for the full text.
