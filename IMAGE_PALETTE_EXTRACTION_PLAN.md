# Plan: image → palette extraction in the `:image` library

This is an implementation plan for adding **image → palette
extraction** (the third improvement from the Hinton blog-post
review) to the sibling `:image` library at
`/Users/kip/Development/image/image`. The `:color` library
already provides everything needed *downstream* of the pixel
phase (`Color.Palette.Cluster`, `Color.Palette.Summarize`,
`Color.Palette.Sort`, the `/spectrum` visualiser); the missing
link is a robust pixel → clusters step that lives where the
pixels live.

## Status (as of `:color` 0.13.0)

* **PR 1 (in `:color`) — done.** The merge & rep helpers are
  lifted into a public `Color.Palette.Cluster` module
  ([cluster.ex](lib/color/palette/cluster.ex)) with five
  exposed functions:

  * `from_colors/2` — bootstrap singleton clusters from
    `Color.new/1` inputs (with optional `:weights`).
  * `merge_until/3` — agglomerative merge until ≤ target count.
    Mass-weighted Oklab centroids; chromatic-axis weighting
    via `:ab_weight`.
  * `merge_pair/2` — merge two clusters explicitly. Public so
    `:image` can stitch K-means output without duplicating the
    centroid update.
  * `representative/2` — centroid-aware swatch pick: highest
    `chroma × mass` for chromatic centroids; closest-to-centroid
    for achromatic.
  * `distance/3` — mass-weighted Oklab distance, exposed so
    `:image` doesn't redefine the metric.

  Cluster shape is documented as a plain map
  (`%{centroid: {l, a, b}, mass:, members: [%{output:, oklab:,
  oklch:, mass:}]}`) so callers building clusters from K-means
  output can construct them directly.

  `Color.Palette.Summarize` is now a thin wrapper over
  `Cluster.from_colors → merge_until → representative`. No API
  break. 21 new unit tests + 6 doctests cover the new module.

* **PR 2 (in `:image`) — ready to start.** Sections below
  describe the work.

## Where the boundary sits

`:color` knows about colours, gamuts, perceptual spaces, and
palettes. `:image` knows about pixels, decoders, resizing,
colourspace conversion, and Nx/Scholar. Image decoding does not
belong in `:color`, and Oklab/Oklch transforms do not belong in
`:image`. The split:

| concern                      | lives in   |
|------------------------------|------------|
| sample pixels from an image  | `:image`   |
| convert pixel batch to Oklab | `:image` (calls `:color`) |
| K-means / clustering         | `:image` (Scholar) |
| centroid → swatch struct     | `:image` |
| sort / summarize / visualise | `:color` |

`:image` already has [Image.Scholar.k_means/2](../../image/lib/image/scholar.ex:52)
which clusters in 8-bit RGB on deduplicated pixel rows; the new
work either teaches that path Oklab + perceptual weighting, or
adds a sibling module for the new pipeline.

## Public surface (proposed)

In the `:image` library:

```elixir
@spec Image.Palette.extract(Vimage.t(), keyword()) :: {:ok, [Color.SRGB.t()]} | {:error, term}

# options:
#   :k                       — clusters (default 14)
#   :final                   — output count (default 5)
#   :max_pixels              — sample cap (default 90_000)
#   :longest_dim             — pre-resize longest dim (default 300)
#   :ab_weight               — chromatic vs lightness weight (default 2.0)
#   :merge_distance          — Oklab merge cutoff (default 0.07)
#   :phantom_min_mass        — phantom-guard mass fraction (default 0.025)
#   :phantom_max_chroma      — phantom-guard chroma cap (default 0.05)
#   :rep_chroma_threshold    — rep-selection cutoff (default 0.03)
#   :seed                    — deterministic init seed (default :hash)
#   :sort                    — :hue_lightness | false (default :hue_lightness)
```

The return is a small list of `Color.SRGB` structs ready to
hand to `Color.Palette.sort/2`, `Color.Palette.tonal/2`, the
`/spectrum` visualiser, etc.

## Algorithm (Hinton, adapted)

Six discrete passes:

### 1. Decode and sample (`:image`)

* `Vimage` in. If image has alpha, drop pixels with alpha < 128.
* Resize so the longest dimension is `:longest_dim` (default 300).
  Use `Vix.Vips.Operation.thumbnail_image!/2` — already used
  elsewhere in `:image`. This is the single biggest perf knob —
  Hinton's "under a second" claim depends on it.
* If pixel count still exceeds `:max_pixels` (default 90 000),
  uniform-stride sample down to that count.

### 2. Convert to Oklab (`:image`, calls `:color`)

* sRGB → linear-sRGB → XYZ → Oklab.
* Vectorised with Nx in a single tensor op rather than
  per-pixel `Color.convert/2`. This is critical: the pixel batch
  is 9k–90k entries, so a per-row Elixir call would dominate.
* New helper `Image.Color.to_oklab(tensor)` (or extend
  `Image.Scholar`) implementing the matrix path inline. The
  reference math is in `Color.Spaces.Oklab` — port the
  coefficients, don't import the per-pixel function.

### 3. K-means++ in Oklab (`:image`, Scholar)

* `Scholar.Cluster.KMeans.fit(oklab_tensor, num_clusters: k, init: :k_means_pp)`.
  Existing `Image.Scholar.k_means/2` already wraps this — extend
  it (or wrap it) to take a pre-converted tensor instead of
  re-deriving from `unique_colors`.
* Apply the **`ab_weight`** by scaling columns 2 and 3 (a, b) of
  the input tensor by `√ab_weight` *before* fitting. Squared
  Euclidean distance in Scholar then sees the right weighting
  with no algorithm changes.
* Determinism: derive the random seed from a hash of eight
  canonical pixels (top-left, centre, four corners + two diag
  midpoints). Hinton's trick — same image → same palette across
  runs.

### 4. Merge near-duplicate clusters (`:image`)

After K-means returns `k` centroids:

1. Wrap each centroid as a `Color.Palette.Cluster` map:

   ```elixir
   %{
     centroid: {l, a, b},
     mass: pixel_count,
     members: assigned_pixels   # list of %{output:, oklab:, oklch:, mass:}
   }
   ```

   `output` is whatever the caller wants returned by
   `representative/2` — typically the original `Color.SRGB`
   pixel struct, but anything is fine.

2. Call `Color.Palette.Cluster.merge_until/3` with the desired
   target count. The threshold-based variant Hinton uses
   (collapse pairs within 0.07 Oklab) can be implemented as a
   short loop calling `Cluster.merge_pair/2` directly when the
   minimum-distance pair is below threshold:

   ```elixir
   def merge_within(clusters, threshold, ab_weight) do
     case closest_pair(clusters, ab_weight) do
       {a, b, d} when d < threshold ->
         merged = Color.Palette.Cluster.merge_pair(a, b)
         merge_within([merged | rest_without(clusters, a, b)], threshold, ab_weight)
       _ ->
         clusters
     end
   end
   ```

   Combine: run `merge_within/3` first to collapse near-dupes,
   then `merge_until/3` to land on the slot count. The cluster
   shape and the distance metric (`Cluster.distance/3`) come
   from `:color` so the algorithm doesn't drift between
   libraries.

### 5. Phantom guard + mass-based slot allocation (`:image`)

* Drop any cluster with `mass < :phantom_min_mass × total_mass`
  AND `centroid_chroma < :phantom_max_chroma`. This filters out
  small pockets of near-grey pixels that would otherwise claim
  a slot.
* Compute `chromatic_mass / total_mass` and allocate the
  `:final` (default 5) slots proportionally between achromatic
  and chromatic buckets. Achromatics are then bucketed into
  dark / mid / light by Oklch L; same-bucket pairs merge.

### 6. Centroid-aware swatch selection (`:image`, calls `:color`)

For each surviving cluster, call
`Color.Palette.Cluster.representative/2`. The implementation
already encodes Hinton's rule:

* `Oklch C(centroid) > :rep_chroma_threshold` →
  highest `chroma × mass` member (the most vivid example,
  weighted so a high-chroma minority can't hijack a hue-shifted
  centroid);
* otherwise → member nearest the centroid in weighted Oklab,
  with member mass as a tiebreaker.

The "in the radius" bound from Hinton's prose maps onto the
mass-weighted chroma: members far from the centroid have
correspondingly small assignment mass after K-means, so their
`chroma × mass` score will rarely beat a near-centroid member's.
If empirical results show outlier-hijacking on real images,
either lower `:ab_weight` (cheaper merges) or pre-filter the
member list before calling `representative/2` (caller's
responsibility — `:color` deliberately doesn't take a radius
parameter to keep the metric simple).

The chosen member's `:output` is returned directly — convert
back to sRGB upstream when constructing members.

* `Image.Color.to_oklab/1` — vectorised sRGB-tensor → Oklab-tensor
  helper (or extend `Image.Scholar` with the matrix path).
* `Image.Palette` — new module wrapping the six-pass pipeline:
  - sample → Oklab tensor
  - K-means via Scholar with ab-weighted columns
  - assignment array (which pixel → which centroid)
  - wrap as `Color.Palette.Cluster` maps and call
    `Cluster.merge_until/3` (and a local "merge within
    threshold" loop using `Cluster.merge_pair/2`)
  - phantom guard + mass allocation (local)
  - call `Color.Palette.Cluster.representative/2` per surviving
    cluster
  - optional `Color.Palette.sort/2` pass before returning

* Optional convenience: `Image.Palette.spectrum/2` returning the
  same hue-bin / lightness-band counts the new
  `Color.Palette.Visualizer.SpectrumView` already renders, so a
  caller can build the histogram view directly from an image
  without going through palette extraction first.

* Add `:color` as a runtime dep in `:image`'s `mix.exs` (it may
  already be there transitively; if not, add it).

## Test strategy

* Twelve fixture images in `test/support/fixtures/palette/` —
  the same set Hinton benchmarked against if obtainable, plus
  edge cases:
  - mostly grey image with one accent
  - high-key (mostly light) image
  - low-key (mostly dark) image
  - photograph with broad hue distribution
  - illustration with a hand-picked five-colour palette
* For each fixture, snapshot the output palette (5 hex strings)
  in a golden file. Drift is significant; review on change.
* Determinism test: run extraction twice with default options;
  assert byte-equal output.
* `:max_pixels` cap test: assert runtime under 1.5 s on the
  largest fixture (Hinton's "under a second" target with some
  CI margin).

## Out of scope (for now)

* Image-aware sort heuristics (e.g. "natural" reading order
  by photographer convention). The existing
  `Color.Palette.sort/2` strategies are sufficient.
* Direct integration with the `/spectrum` visualiser route
  (uploading an image through the browser). That's a separate
  feature once the extraction core is in place — at minimum it
  needs a multipart upload handler and a temp-file lifecycle.
* GPU/EXLA backend selection. Use Scholar's defaults; revisit if
  the test-fixture suite shows slow runs.

## Minor follow-ups (revisit after PR 2 lands)

1. **Expose `Color.Palette.Sort`'s gray-vs-chromatic split as a
   public helper** (`Color.Palette.Sort.partition_grays/2`).
   `:image`'s phantom guard wants the same exact partition
   logic, and reimplementing risks drift in the chroma
   threshold default.

2. **Add a `:weights` example to the existing
   `Color.Palette.summarize/3` doctest.** Once `:image` is
   feeding cluster mass through, that's the canonical use case
   and is currently undocumented at the example level.

3. **Spectrum visualiser image upload.** The `/spectrum` route
   currently takes a textarea of colours. Once `:image` exposes
   the histogram primitive, the route could optionally accept
   a multipart image upload.

None block PR 2.
