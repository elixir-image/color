# Changelog

All notable changes to this project are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## Color version 0.3.0

### Added

* `Color.ANSI` module for parsing and emitting ANSI SGR colour escape sequences. Supports 16-colour, 256-colour indexed, and 24-bit truecolor forms, with perceptual nearest-palette matching (CIEDE2000) when encoding to the 16- or 256-colour palette. Includes `parse/1`, `to_string/2`, `wrap/3`, `nearest_256/1`, `nearest_16/1`, `palette_256/0`, `palette_16/0`, and a typed `Color.ANSI.ParseError` exception.

* Top-level `Color.to_hex/1` and `Color.to_css/1,2` convenience functions that accept any input `Color.new/1` accepts and raise a typed exception on failure.

### Changed

* Changed the module `Color.CSSNames` to `Color.CSS.Names`

## Color version 0.2.0

### Added

* Twenty-one color-space struct modules covering CIE, modern perceptual, HDR, video, device, and web spaces: `Color.SRGB`, `Color.AdobeRGB`, `Color.RGB` (linear, in any of 24 named working spaces), `Color.Lab`, `Color.LCHab`, `Color.Luv`, `Color.LCHuv`, `Color.XYZ`, `Color.XYY`, `Color.Oklab`, `Color.Oklch`, `Color.HSLuv`, `Color.HPLuv`, `Color.Hsl`, `Color.Hsv`, `Color.CMYK`, `Color.YCbCr`, `Color.JzAzBz`, `Color.ICtCp`, `Color.IPT`, `Color.CAM16UCS`.

* Top-level `Color.new/1,2`, `Color.convert/2,3,4`, `Color.convert_many/2,3,4`, `Color.luminance/1`, `Color.sort/2`, `Color.premultiply/1`, `Color.unpremultiply/1`.

* Chromatic adaptation (`Color.XYZ.adapt/3`) with six methods: `:bradford`, `:xyz_scaling`, `:von_kries`, `:sharp`, `:cmccat2000`, `:cat02`. `Color.XYZ.apply_bpc/3` for black point compensation.

* ICC rendering intents wired into `Color.convert/3,4`: `:relative_colorimetric` (default), `:absolute_colorimetric`, `:perceptual`, `:saturation`. Optional `bpc: true` and `adaptation:` method override.

* `Color.ICC.Profile` matrix-profile reader covering ICC v2/v4 RGB→XYZ profiles with `curv` LUT and `para` parametric (types 0–4) tone response curves; `load/1`, `parse/1`, `to_xyz/2`, `from_xyz/2`.

* Color difference metrics (`Color.Distance`): CIE76, CIE94, CIEDE2000 (verified against Sharma 2005), and CMC l:c.

* Contrast (`Color.Contrast`): WCAG 2.x relative luminance and contrast ratio, APCA W3 0.1.9, contrast-aware `pick_contrasting/2`.

* Color mixing and gradients (`Color.Mix`) with the default Oklab interpolation space and CSS Color 4 hue-interpolation modes.

* Gamut checking and mapping (`Color.Gamut`) with both `:clip` and the CSS Color 4 Oklch binary-search perceptual algorithm.

* Color harmonies (`Color.Harmony`) — complementary, analogous, triadic, tetradic, split-complementary — in any cylindrical space.

* Color temperature (`Color.Temperature`): McCamy CCT, Planckian and CIE daylight loci, `xyz/2`.

* CSS Color Module Level 4 / 5 parser and serialiser (`Color.CSS`): hex, named colors, all standard color functions, `color()` with display-p3 / a98-rgb / prophoto-rgb / rec2020 / xyz, `device-cmyk()`, `color-mix()`, relative color syntax, `none`, and `calc()` expressions.

* CSS named colors (`Color.CSSNames`): all 148 CSS Color Module Level 4 names plus `chromagreen` and `chromablue`. Atom and snake-case input. Reverse `nearest/1` lookup via CIEDE2000.

* `~COLOR` sigil (`Color.Sigil`) for compile-time color literals, compile-fenced behind Elixir 1.15.

* Spectral pipeline (`Color.Spectral` + `Color.Spectral.Tables`): CIE 1931 2° and CIE 1964 10° standard observer CMFs, D65 / D50 / A / E illuminant SPDs, emissive and reflective integration, metamerism index.

* All sixteen CSS Compositing Level 1 blend modes (`Color.Blend`).

* Transfer functions (`Color.Conversion.Lindbloom`): sRGB, gamma 2.2 / 1.8, L*, BT.709, BT.2020, PQ (SMPTE ST 2084), HLG, Adobe RGB γ.

* Typed exception modules under `Color.*Error` for every fallible function. Every error returns `{:ok, _}` or `{:error, %SomeError{...}}` with semantic fields.

* Public `Color.Behaviour` declaring the `to_xyz/1` and `from_xyz/1` contract that every color-space struct module satisfies.

* `Color.is_color/1` and `Color.is_css_name/1` compile-time guards plus `Color.color?/1`, `Color.css_name?/1`, and `Color.validate_transparency/1` migration helpers.

* `@type t` on every public color-space struct module and `@spec` annotations across the public API.

* Benchee benchmark suite under `bench/` covering single-color conversions, batch vs `Enum.map`, and the `:persistent_term` working-space cache.

* Property-based test suite (`test/property_test.exs`) covering round-trip identity, alpha preservation, hue wrap-around, gamut-mapping invariance, ΔE symmetry, mix endpoint identity, and WCAG contrast bounds across every supported space.

### Performance

* `Color.RGB.WorkingSpace.rgb_conversion_matrix/1` results are cached in `:persistent_term` so repeated lookups for the same named space are constant-time after the first call.

