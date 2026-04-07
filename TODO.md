# TODO

Features identified by comparing against the canonical color libraries
(Little CMS, OpenColorIO, Skia, Palette, java.awt.color) and the
`Image.Color` module in sibling project `../image`. Ordered by tier
from most to least impactful.

Tier 1 has been implemented — see `Color.Contrast`, `Color.Mix`,
`Color.Gamut`, `Color.Harmony`, `Color.Temperature`, `Color.CSS`,
`Color.Blend`, and the reverse lookups on `Color.CSSNames` and
`Color.RGB.WorkingSpace`.

## Tier 2 — valuable, more work

### ICC matrix-profile reading

Parse the common ICC v2/v4 "matrix profile" case: the `rXYZ`, `gXYZ`,
`bXYZ` tags (primary chromaticities expressed as XYZ values in the PCS)
plus the `rTRC`, `gTRC`, `bTRC` tags (tone response curves, as
parametric curves or 1D LUTs). That's enough to load `Display P3.icc`,
`sRGB IEC61966-2.1.icc`, most camera profiles, and most scanner
profiles. Full ICC v4 CMM is a multi-month project; matrix profiles
alone are ~500–1000 LOC.

Suggested module: `Color.ICC.Profile`.

### Rendering intents in `Color.convert/2`

Wire `:absolute_colorimetric | :relative_colorimetric | :perceptual |
:saturation` into `convert/2` as an option. `:relative_colorimetric` is
today's default behaviour (Bradford adapt + no gamut clip).
`:perceptual` should route out-of-gamut colors through
`Color.Gamut.to_gamut/2,3`. `:saturation` would preserve chroma at the
cost of hue shift. `:absolute` disables adaptation entirely.

### Black point compensation

Optional flag on rendering intents that matches the darkest black
between the source and destination so shadow detail isn't crushed.
Small on top of ICC + rendering intents.

### Batch conversion API

`Color.convert_many/2` that takes a list (or stream) of colors and
applies one conversion. The hot-path should skip per-call overhead:
compute matrices once, then fold over the list. Genuinely fast for
megapixel-scale work. An optional `:nx` dep could re-enter here purely
for the batched path if it ever proves measurably better on large N.

### Spectral reflectance / SPDs

Load illuminant spectral power distributions (D65, A, F-series) and
object spectral reflectances. Enables metamer detection — two colors
that match under one light and diverge under another. Niche outside
paint/print/science work.

Suggested module: `Color.Spectral`.

### Relative luminance helper (additional contexts)

`Color.luminance/1` is already in `Color.Contrast` as
`relative_luminance/1`; consider also exposing it at the top level for
discoverability.

### Sort / rank by perceptual criteria

`Color.sort/2` with `:by` options like `:lightness`, `:chroma`,
`:hue`, `:hlv` (matches the algorithm Image.Color.sort/2 uses today).

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
