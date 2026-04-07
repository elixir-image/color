# TODO

Features identified by comparing against the canonical color libraries
(Little CMS, OpenColorIO, Skia, Palette, java.awt.color) and the
`Image.Color` module in sibling project `../image`. Ordered by tier
from most to least impactful.

Tier 1 has been implemented — see `Color.Contrast`, `Color.Mix`,
`Color.Gamut`, `Color.Harmony`, `Color.Temperature`, `Color.CSS`,
`Color.Blend`, and the reverse lookups on `Color.CSSNames` and
`Color.RGB.WorkingSpace`.

Tier 2 items marked ✅ below have been implemented:

* ✅ Rendering intents in `Color.convert/2,3,4`
  (`:relative_colorimetric`, `:absolute_colorimetric`, `:perceptual`,
  `:saturation`, plus `:adaptation` method selection).
* ✅ Black point compensation via `Color.XYZ.apply_bpc/3` and the
  `bpc: true` option on `Color.convert`.
* ✅ Spectral reflectance / SPDs — see `Color.Spectral` and
  `Color.Spectral.Tables` (CIE 1931 2° and CIE 1964 10° CMFs, D65,
  D50, A, E illuminants, emissive and reflective integration,
  metamerism helper).
* ✅ `Color.luminance/1` at the top level, delegating to
  `Color.Contrast.relative_luminance/1`.
* ✅ `Color.sort/2` with `:by` presets (`:luminance`, `:lightness`,
  `:oklab_l`, `:chroma`, `:oklch_c`, `:hue`, `:oklch_h`, `:hlv`) or
  a custom sort-key function, plus `:order`.

## Tier 2 — remaining

### ICC matrix-profile reading

Parse the common ICC v2/v4 "matrix profile" case: the `rXYZ`, `gXYZ`,
`bXYZ` tags (primary chromaticities expressed as XYZ values in the PCS)
plus the `rTRC`, `gTRC`, `bTRC` tags (tone response curves, as
parametric curves or 1D LUTs). That's enough to load `Display P3.icc`,
`sRGB IEC61966-2.1.icc`, most camera profiles, and most scanner
profiles. Full ICC v4 CMM is a multi-month project; matrix profiles
alone are ~500–1000 LOC.

Suggested module: `Color.ICC.Profile`.

### Batch conversion API

`Color.convert_many/2` that takes a list (or stream) of colors and
applies one conversion. The hot-path should skip per-call overhead:
compute matrices once, then fold over the list. Genuinely fast for
megapixel-scale work. An optional `:nx` dep could re-enter here purely
for the batched path if it ever proves measurably better on large N.

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
