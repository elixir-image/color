# TODO

Features identified by comparing against the canonical color libraries
(Little CMS, OpenColorIO, Skia, Palette, java.awt.color) and the
`Image.Color` module in sibling project `../image`. Ordered by tier
from most to least impactful.

Tier 1 has been implemented — see `Color.Contrast`, `Color.Mix`,
`Color.Gamut`, `Color.Harmony`, `Color.Temperature`, `Color.CSS`,
`Color.Blend`, and the reverse lookups on `Color.CSSNames` and
`Color.RGB.WorkingSpace`.

All Tier 2 items have been implemented:

* ✅ Rendering intents in `Color.convert/2,3,4`
  (`:relative_colorimetric`, `:absolute_colorimetric`, `:perceptual`,
  `:saturation`, plus `:adaptation` method selection).
* ✅ Black point compensation via `Color.XYZ.apply_bpc/3` and the
  `bpc: true` option on `Color.convert`.
* ✅ Spectral reflectance / SPDs — see `Color.Spectral` and
  `Color.Spectral.Tables`.
* ✅ `Color.luminance/1` at the top level.
* ✅ `Color.sort/2` with `:by` presets.
* ✅ `Color.ICC.Profile` matrix profile reader (`load/1`, `parse/1`,
  `to_xyz/2`, `from_xyz/2`). Supports `curv` LUT and `para`
  parametric TRCs.
* ✅ `Color.convert_many/2,3,4` batch conversion API.

## Nice to have — all implemented

* ✅ Performance benchmarks — see `bench/conversions.exs`.
* ✅ Property-based tests — see `test/property_test.exs` (58
  properties covering round-trip identity, alpha preservation, hue
  wrap-around, gamut mapping invariance, ΔE symmetry, mix endpoint
  identity, and WCAG contrast bounds).
* ✅ `Color.Behaviour` declaring `to_xyz/1` and `from_xyz/1`
  callbacks; 20 of 21 space modules conform.
* ✅ Batch conversion API.
* ✅ ICC matrix-profile reader.
* ✅ API symmetry — `convert/3` accepts `working_space:` in its
  options keyword, with `convert/4` retained as positional sugar.

## Tier 3 — domain-specific or niche

### Soft-proofing

Simulate a target device (usually a printer) on an RGB display.
Requires ICC + rendering intents + device link chaining. Standard
lcms2 / OCIO feature.

### Device link profiles

Single-profile shortcut that bypasses the PCS for faster
source-to-destination transforms (e.g. CMYK-to-CMYK). Builds on ICC.

### OpenColorIO config reading

Parse `config.ocio` YAML: roles, looks, displays/views, LUT chains.
Essential in VFX / film post. Big undertaking; probably best as a
separate `color_ocio` dependency.

### 3D LUT reading and application

`.cube`, `.3dl`, `.dat` format readers. Colour grading workflow.
Tri-linear and tetrahedral interpolation.

### Pantone / Munsell / NCS lookups

Commercial licensing minefield for Pantone; Munsell is free (USB
dataset available from the University of Eastern Finland). Niche,
mostly interesting for print and paint.

### Additional Color Appearance Models

CAM02, Hunt, RLAB, Nayatani. CAM16 is already implemented. Research
interest only.

## Tier 4 — skip unless explicitly requested

- Display calibration (needs colorimeter hardware).
- Full ICC v4 CMM with all tag types and LUT profiles. Use `lcms2`
  via a NIF if this is ever needed.
- Colour-picker UI helpers — belongs in a UI library, not here.

## `Image.Color` replacement work

Tracked separately — see the module docs in `Color` for the migration
plan. Blockers for a true drop-in swap:

- Integer-list ↔ unit-range float adapter layer (at the Image
  boundary, not this library).
- Guards `Color.is_color/1` and `Color.is_css_name/1` (easy, small).
- `Color.validate_transparency/1` for the `:transparent | :opaque |
  :none | float | 0..255` union used by Image.
- ICC profile recognition for file paths (Tier 2 item above).
- `Image.Color.sort/2` — trivially reimplementable from
  `Color.Harmony.rotate_hue/2` + `Color.Contrast.relative_luminance/1`
  or moved verbatim to the Image side.
