defmodule Color.Palette.Cluster do
  @moduledoc """
  Low-level perceptual clustering primitives in Oklab.

  This module is the seam between `Color.Palette.Summarize`
  (which clusters arbitrary colour lists) and the
  [`:image`](https://hex.pm/packages/image) library's pixel
  extraction pipeline (which clusters image pixels via Scholar
  K-means and then collapses near-duplicates). Both call the
  same primitives so the algorithm doesn't drift between the
  two callers.

  Two operations are exposed:

  * `merge_until/3` — agglomerative bottom-up merging. Takes a
    list of clusters and merges the closest pair (mass-weighted
    Oklab distance) repeatedly until the target count is
    reached.

  * `representative/2` — given a cluster, pick one of its
    members as the cluster's swatch using a centroid-aware
    rule. **Highest-chroma** member when the centroid is
    chromatic; **closest to centroid** when achromatic.

  A small helper, `from_colors/2`, builds initial singleton
  clusters from a list of colour inputs (with optional weights),
  which is what `Color.Palette.Summarize` uses to bootstrap.

  ## Cluster shape

  A cluster is a plain map with three keys:

      %{
        centroid: {l, a, b},   # Oklab, mass-weighted mean of members
        mass:     number,      # sum of member masses
        members:  [member]     # the originals that fell into this cluster
      }

  A member is also a plain map:

      %{
        output: term,          # what to return when this member is picked
        oklab:  %Color.Oklab{},
        oklch:  %Color.Oklch{}, # null L/C/H normalised to 0.0
        mass:   number
      }

  Members carry both Oklab (rectangular, used for distance) and
  Oklch (cylindrical, used for chroma checks) so callers don't
  re-convert during inner loops.

  ## Distance and the chromatic-axis weight

  Distance between two clusters is mass-aware Euclidean in Oklab
  with the chromatic axes scaled by `ab_weight`:

      d² = ΔL² + ab_weight · (Δa² + Δb²)

  Default `ab_weight = 2.0`. The intuition: hue mismatch is more
  perceptually salient than lightness mismatch, so weighting
  `(a, b)` higher than `L` keeps clusters from accidentally
  merging across colour-category lines.

  ## Use from the `:image` library

  `:image`'s K-means pass produces a centroid array and a
  per-pixel cluster-assignment array. To collapse near-duplicate
  centroids and pick swatches, build clusters of the shape
  above (one member per pixel, or per uniqued pixel) and call
  `merge_until/3` followed by `representative/2`.

  """

  @default_ab_weight 2.0
  @default_rep_chroma_threshold 0.03

  @type centroid :: {number(), number(), number()}

  @type member :: %{
          required(:output) => term(),
          required(:oklab) => Color.Oklab.t(),
          required(:oklch) => Color.Oklch.t(),
          required(:mass) => number()
        }

  @type cluster :: %{
          required(:centroid) => centroid(),
          required(:mass) => number(),
          required(:members) => [member()]
        }

  # ---- bootstrap from colour inputs -------------------------------------

  @doc """
  Builds initial singleton clusters from a list of colour
  inputs. Each input becomes its own cluster; the cluster
  centroid is the input's Oklab coordinate and the cluster's
  sole member is a fully-prepared member map.

  ### Arguments

  * `colors` is a list of values accepted by `Color.new/1`.

  ### Options

  * `:weights` is an optional list of non-negative numbers, the
    same length as `colors`. Default: every colour weighted
    `1.0`.

  ### Returns

  * A list of `t:cluster/0` maps, one per input.

  ### Examples

      iex> [c] = Color.Palette.Cluster.from_colors(["#ff0000"])
      iex> c.mass
      1.0
      iex> length(c.members)
      1

      iex> [_, _] = Color.Palette.Cluster.from_colors(["#ff0000", "#0000ff"], weights: [3.0, 1.0])

  """
  @spec from_colors(list(Color.input()), keyword()) :: [cluster()]
  def from_colors(colors, options \\ []) when is_list(colors) do
    weights =
      case Keyword.get(options, :weights) do
        nil -> List.duplicate(1.0, length(colors))
        list when is_list(list) -> validate_weights!(list, length(colors))
      end

    [colors, weights]
    |> Enum.zip()
    |> Enum.map(fn {color, weight} ->
      member = build_member(color, weight)

      %{
        centroid: {member.oklab.l, member.oklab.a, member.oklab.b},
        mass: member.mass,
        members: [member]
      }
    end)
  end

  defp build_member(color, weight) do
    {:ok, srgb} = Color.new(color)
    {:ok, oklab} = Color.convert(srgb, Color.Oklab)
    {:ok, oklch} = Color.convert(srgb, Color.Oklch)

    %{
      output: srgb,
      oklab: oklab,
      oklch: %{oklch | l: oklch.l || 0.0, c: oklch.c || 0.0, h: oklch.h || 0.0},
      mass: weight * 1.0
    }
  end

  defp validate_weights!(weights, expected_length) do
    cond do
      length(weights) != expected_length ->
        raise Color.PaletteError,
          reason: :invalid_weights,
          detail: ":weights length must equal length(colors) (#{expected_length})"

      not Enum.all?(weights, &(is_number(&1) and &1 >= 0)) ->
        raise Color.PaletteError,
          reason: :invalid_weights,
          detail: ":weights must be non-negative numbers"

      true ->
        weights
    end
  end

  # ---- agglomerative merge ----------------------------------------------

  @doc """
  Merges the closest cluster pair (by mass-weighted Oklab
  distance) until at most `target_count` clusters remain.

  Centroids are updated as the mass-weighted mean of the two
  merged clusters; member lists are concatenated. If the input
  already has `≤ target_count` clusters the input is returned
  unchanged.

  ### Arguments

  * `clusters` is a list of `t:cluster/0` maps.

  * `target_count` is the maximum number of clusters in the
    output.

  ### Options

  * `:ab_weight` is the multiplier on the chromatic axes
    `(a, b)` in the Oklab distance metric, relative to
    lightness `L`. Default `2.0`.

  ### Returns

  * A list of `t:cluster/0` maps, length `≤ target_count`.

  ### Examples

      iex> [c] =
      ...>   Color.Palette.Cluster.from_colors(["#ff0000", "#fe0202"])
      ...>   |> Color.Palette.Cluster.merge_until(1)
      iex> length(c.members)
      2

      iex> Color.Palette.Cluster.merge_until([], 5)
      []

  ### Complexity

  Pairwise distances are recomputed each merge, giving an
  `O(n³)` worst case in the number of input clusters. Suitable
  for the typical palette sizes (tens of clusters); for
  thousands of inputs, run an upstream K-means pass and call
  this only on the resulting centroids.

  """
  @spec merge_until([cluster()], non_neg_integer(), keyword()) :: [cluster()]
  def merge_until(clusters, target_count, options \\ [])
      when is_list(clusters) and is_integer(target_count) and target_count >= 0 do
    ab_weight = ab_weight!(options)

    do_merge_until(clusters, target_count, ab_weight)
  end

  defp do_merge_until(clusters, target, _ab_weight) when length(clusters) <= target,
    do: clusters

  defp do_merge_until(clusters, target, ab_weight) do
    {ci, cj, others} = pop_closest_pair(clusters, ab_weight)
    do_merge_until([merge_pair(ci, cj) | others], target, ab_weight)
  end

  defp pop_closest_pair(clusters, ab_weight) do
    indexed = Enum.with_index(clusters)

    {ia, ib, _} =
      for(
        {a, ia} <- indexed,
        {b, ib} <- indexed,
        ia < ib,
        do: {ia, ib, distance(a.centroid, b.centroid, ab_weight)}
      )
      |> Enum.min_by(fn {_, _, d} -> d end)

    ci = Enum.at(clusters, ia)
    cj = Enum.at(clusters, ib)

    others =
      clusters
      |> Enum.with_index()
      |> Enum.reject(fn {_, idx} -> idx == ia or idx == ib end)
      |> Enum.map(fn {c, _} -> c end)

    {ci, cj, others}
  end

  @doc """
  Merges two clusters into one. The merged centroid is the
  mass-weighted mean of the inputs; the merged member list is
  the concatenation of the inputs'. Public so the
  `:image` library can re-use it after Scholar's K-means
  produces clusters with explicit assignment masses.

  ### Arguments

  * `a` is a `t:cluster/0` map.

  * `b` is a `t:cluster/0` map.

  ### Returns

  * A single `t:cluster/0` map with the combined mass and
    members.

  ### Examples

      iex> [a, b] = Color.Palette.Cluster.from_colors(["#ff0000", "#0000ff"])
      iex> merged = Color.Palette.Cluster.merge_pair(a, b)
      iex> merged.mass
      2.0
      iex> length(merged.members)
      2

  """
  @spec merge_pair(cluster(), cluster()) :: cluster()
  def merge_pair(%{centroid: ca, mass: ma, members: ms_a}, %{centroid: cb, mass: mb, members: ms_b}) do
    total = ma + mb
    {al, aa, ab} = ca
    {bl, ba, bb} = cb

    centroid = {
      (al * ma + bl * mb) / total,
      (aa * ma + ba * mb) / total,
      (ab * ma + bb * mb) / total
    }

    %{centroid: centroid, mass: total, members: ms_a ++ ms_b}
  end

  @doc """
  Mass-weighted Euclidean distance between two Oklab points,
  with the chromatic axes `(a, b)` scaled by `ab_weight`
  relative to lightness `L`.

  Exposed so the `:image` library can use the same metric for
  its own merge / dedupe passes without redefining the formula.

  ### Arguments

  * `a` is the first Oklab point as `{l, a, b}`.

  * `b` is the second Oklab point as `{l, a, b}`.

  * `ab_weight` is the multiplier on `(a, b)` relative to `L`.
    Pass `2.0` to match the default merging metric.

  ### Returns

  * A non-negative number.

  ### Examples

      iex> Color.Palette.Cluster.distance({0.5, 0.0, 0.0}, {0.5, 0.0, 0.0}, 2.0)
      0.0

      iex> Color.Palette.Cluster.distance({0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, 2.0)
      1.0

  """
  @spec distance(centroid(), centroid(), number()) :: float()
  def distance({l1, a1, b1}, {l2, a2, b2}, ab_weight) do
    dl = l1 - l2
    da = a1 - a2
    db = b1 - b2
    :math.sqrt(dl * dl + ab_weight * (da * da + db * db))
  end

  # ---- representative selection -----------------------------------------

  @doc """
  Picks one of a cluster's members as the cluster's swatch and
  returns that member's `:output` field.

  The rule is centroid-aware:

  * If the centroid is **chromatic** (Oklch C above
    `:rep_chroma_threshold`), prefer the member with the
    largest `mass × Oklch chroma`. This favours the most vivid
    representative while still honouring weight, so under
    heavy mass weighting the rep tracks the centroid's hue
    rather than being hijacked by a high-chroma minority.

  * If the centroid is **achromatic**, prefer the member
    nearest the centroid in mass-weighted Oklab distance, with
    member mass as a tiebreaker. This keeps the rep on the
    cluster's tonal axis instead of leaning warm or cool.

  ### Arguments

  * `cluster` is a `t:cluster/0` map.

  ### Options

  * `:ab_weight` — see `merge_until/3`. Default `2.0`.

  * `:rep_chroma_threshold` — Oklch chroma above which the
    chromatic branch is taken. Default `0.03`.

  ### Returns

  * The `:output` field of the chosen member (typically a
    `%Color.SRGB{}` struct, but anything the caller stored when
    building the member).

  ### Examples

      iex> [cluster] =
      ...>   Color.Palette.Cluster.from_colors(["#ff0000", "#cc4040"])
      ...>   |> Color.Palette.Cluster.merge_until(1)
      iex> Color.Palette.Cluster.representative(cluster) |> Color.to_hex()
      "#ff0000"

  """
  @spec representative(cluster(), keyword()) :: term()
  def representative(%{centroid: centroid, members: members}, options \\ [])
      when is_list(members) and members != [] do
    ab_weight = ab_weight!(options)
    rep_chroma_threshold = rep_chroma_threshold!(options)

    {_l, a, b} = centroid
    centroid_chroma = :math.sqrt(a * a + b * b)

    pick =
      if centroid_chroma > rep_chroma_threshold do
        Enum.max_by(members, fn m -> m.oklch.c * m.mass end)
      else
        Enum.min_by(members, fn m ->
          d = distance(centroid, {m.oklab.l, m.oklab.a, m.oklab.b}, ab_weight)
          {d, -m.mass}
        end)
      end

    pick.output
  end

  # ---- options ----------------------------------------------------------

  defp ab_weight!(options) do
    value = Keyword.get(options, :ab_weight, @default_ab_weight)

    unless is_number(value) and value > 0.0 do
      raise Color.PaletteError,
        reason: :invalid_ab_weight,
        detail: ":ab_weight must be a positive number"
    end

    value
  end

  defp rep_chroma_threshold!(options) do
    value = Keyword.get(options, :rep_chroma_threshold, @default_rep_chroma_threshold)

    unless is_number(value) and value >= 0.0 do
      raise Color.PaletteError,
        reason: :invalid_rep_chroma_threshold,
        detail: ":rep_chroma_threshold must be a non-negative number"
    end

    value
  end
end
