# TODO

Features identified by comparing against the canonical colour libraries
(Little CMS, OpenColorIO, Skia, Palette, java.awt.color) and the `Image.Color`
module in the sibling `../image` project. Tiers 1 and 2 are shipped; what
remains is domain-specific, and the `Image.Color` replacement work.

## Open

### `Image.Color` replacement

Blockers for a true drop-in swap; the migration plan is in the `Color` moduledoc.

* [ ] **Integer-list to unit-range float adapter** — at the Image boundary, not in this library.
* [ ] **Guards `Color.is_color/1` and `Color.is_css_name/1`** — easy and small.
* [ ] **`Color.validate_transparency/1`** — for the `:transparent | :opaque | :none | float | 0..255` union Image uses.
* [ ] **ICC profile recognition for file paths** — builds on the `Color.ICC.Profile` reader.
* [ ] **`Image.Color.sort/2`** — trivially reimplementable from `Color.Harmony.rotate_hue/2` and `Color.Contrast.relative_luminance/1`, or moved verbatim to the Image side.

### Tier 3 — domain-specific

* [ ] **Soft-proofing** — simulate a target device (usually a printer) on an RGB display; needs ICC, rendering intents and device-link chaining. Standard lcms2 / OCIO feature.
* [ ] **Device link profiles** — a single-profile shortcut that bypasses the PCS for faster source-to-destination transforms such as CMYK to CMYK. Builds on ICC.
* [ ] **3D LUT reading and application** — `.cube`, `.3dl` and `.dat` readers with tri-linear and tetrahedral interpolation, for colour-grading workflows.
* [ ] **Additional colour appearance models** — CAM02, Hunt, RLAB, Nayatani. CAM16 exists; the rest are research interest only.

## Deferred

* [ ] **OpenColorIO config reading** — parse `config.ocio`: roles, looks, displays and views, LUT chains. Essential in VFX post but a big undertaking; probably a separate `color_ocio` package.
* [ ] **Pantone / Munsell / NCS lookups** — Pantone is a licensing minefield; Munsell is free (University of Eastern Finland dataset). Niche, mostly print and paint.
* [ ] **Display calibration** — needs colorimeter hardware; skip unless explicitly requested.
* [ ] **Full ICC v4 CMM** — all tag types and LUT profiles. Use `lcms2` via a NIF if ever needed.
* [ ] **Colour-picker UI helpers** — belong in a UI library, not here.

## Done

* [x] **CI matrix on the current standard** — bumped the 1.20 rows to `1.20.4`, added an OTP 29 row and moved the lint marker to it, upgraded `actions/checkout` to `@v5`. 2026-09-21.
* [x] **API symmetry** — `convert/3` accepts `working_space:` in its options, with `convert/4` retained as positional sugar.
* [x] **`Color.Behaviour`** — declares `to_xyz/1` and `from_xyz/1`; 20 of 21 space modules conform.
* [x] **Property-based tests** — `test/property_test.exs`, 58 properties covering round-trip identity, alpha preservation, hue wrap-around, gamut mapping invariance, ΔE symmetry, mix endpoint identity and WCAG contrast bounds.
* [x] **Performance benchmarks** — `bench/conversions.exs`.
* [x] **`Color.convert_many/2,3,4`** — batch conversion API.
* [x] **`Color.ICC.Profile`** — matrix profile reader (`load/1`, `parse/1`, `to_xyz/2`, `from_xyz/2`) supporting `curv` LUT and `para` parametric TRCs.
* [x] **`Color.sort/2`** — with `:by` presets.
* [x] **`Color.luminance/1`** — at the top level.
* [x] **Spectral reflectance and SPDs** — `Color.Spectral` and `Color.Spectral.Tables`.
* [x] **Black point compensation** — `Color.XYZ.apply_bpc/3` and `bpc: true` on `Color.convert`.
* [x] **Rendering intents** — `:relative_colorimetric`, `:absolute_colorimetric`, `:perceptual` and `:saturation` in `Color.convert/2,3,4`, plus `:adaptation` method selection.
* [x] **Tier 1** — `Color.Contrast`, `Color.Mix`, `Color.Gamut`, `Color.Harmony`, `Color.Temperature`, `Color.CSS`, `Color.Blend`, and the reverse lookups on `Color.CSSNames` and `Color.RGB.WorkingSpace`.
