# Benchmarks

Benchee scripts for the hot conversion paths. Run with:

```sh
mix run bench/conversions.exs
```

Each script runs warmup + measurement at modest budgets so the whole
suite finishes in a few seconds. Edit the `time:` and `warmup:` keys
on the `Benchee.run/2` calls if you want longer runs.

## What's measured

* **Single-color conversions** to the most-used target spaces
  (`XYZ`, `Lab`, `Oklab`, `Oklch`, `JzAzBz`, `CAM16UCS`).

* **Round-trip** SRGB → Lab → SRGB.

* **`Color.Distance`** — `delta_e_2000` and `delta_e_76`.

* **`Color.Gamut`** — `in_gamut?` and `to_gamut` for a wide-gamut
  Display P3 color mapped into sRGB via the CSS Color 4 Oklch
  perceptual algorithm.

* **`Color.new`** — sRGB list (float and 0..255 integer), Oklab
  list, hex string, CSS named color.

* **`Color.Mix.mix`** — interpolation in Oklab.

* **`Color.CSS.parse`** — `oklch()` form.

* **`Color.Contrast.wcag_ratio`**.

* **Batch vs map** — `Color.convert_many/2` vs
  `Enum.map(_, &Color.convert/2)` over a 1000-element list, for both
  `Color.Lab` and `Color.Oklch` targets. The batch path wins more on
  expensive targets (Oklch) than on the simple ones (Lab).

* **Working-space matrix cache** — `Color.RGB.WorkingSpace.rgb_conversion_matrix/1`
  on already-cached spaces, to verify the `:persistent_term` lookup
  stays in the tens-of-nanoseconds range.

## Adding new benchmarks

Each `Benchee.run/2` call takes a map of name → 0-arity function.
Group related benchmarks into a single call so they share the
warmup phase. Pass `print: [fast_warning: false]` to suppress the
"this benchmark runs in less than X μs" warnings, which are
expected for our nanosecond-scale operations.
