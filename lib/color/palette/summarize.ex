defmodule Color.Palette.Summarize do
  @moduledoc """
  Reduce an arbitrary list of colours to *k* representative
  colours by perceptually-uniform clustering.

  This module is a thin wrapper over `Color.Palette.Cluster`. It
  takes a list of colour inputs, builds initial singleton
  clusters, runs the agglomerative merge to *k* survivors, and
  picks one member from each survivor as the swatch.

  Both the merge step and the rep-selection step are exposed
  publicly on `Color.Palette.Cluster` so the
  [`:image`](https://hex.pm/packages/image) library's pixel
  extraction pipeline can call exactly the same primitives
  (after a Scholar K-means pass) without algorithmic drift.

  ## Algorithm

  Each input colour starts as its own cluster; the closest pair
  (by mass-weighted Oklab distance, chromatic axes weighted
  twice as much as lightness) is merged repeatedly until *k*
  clusters remain. Each cluster's representative is then chosen
  by `Color.Palette.Cluster.representative/2`:

  * **chromatic centroids** → highest `chroma × mass` member
    (the most vivid example, weighted by how often it appears);

  * **achromatic centroids** → member nearest the centroid in
    weighted Oklab, with mass as tiebreaker.

  See `Color.Palette.Cluster` for the full algorithmic
  discussion.

  ## When to use this vs `Color.Palette.Sort`

  * **Sort** orders an existing list of colours; the output has
    the same number of colours as the input.

  * **Summarize** *reduces* the list to a smaller representative
    set. Run it before sorting when you have a large bag of
    near-duplicate swatches.

  ## Complexity

  Pairwise distance is recomputed each merge, giving an
  `O(n³)` worst case. This is fine for the typical palette
  sizes (tens of colours) the rest of `Color.Palette` works
  with; for thousands of inputs (e.g. raw image pixels), use a
  dedicated K-means pass upstream and call `summarize/3` (or
  `Color.Palette.Cluster.merge_until/3`) only on the resulting
  cluster centroids.

  """

  alias Color.Palette.Cluster

  @valid_keys [:weights, :ab_weight, :rep_chroma_threshold]

  @doc """
  Reduces a list of colours to at most `k` representative
  colours.

  ### Arguments

  * `colors` is a list of values accepted by `Color.new/1` —
    hex strings, CSS named colours, `%Color.SRGB{}` structs,
    Oklch structs, etc.

  * `k` is the maximum number of colours in the output. If the
    input has fewer than `k` distinct entries, the output may
    be shorter.

  ### Options

  * `:weights` is an optional list of non-negative numbers, the
    same length as `colors`. Each weight is the relative mass
    of its input colour during clustering. Default: every
    colour weighted `1.0`.

  * `:ab_weight` is the multiplier on the chromatic axes
    `(a, b)` in the Oklab distance metric, relative to
    lightness `L`. Default `2.0`.

  * `:rep_chroma_threshold` is the Oklch chroma above which the
    representative member is the **highest-chroma** original
    member of its cluster. Below this threshold, the
    representative is the **closest to the centroid** in
    weighted Oklab. Default `0.03`.

  ### Returns

  * A list of `%Color.SRGB{}` structs (one per surviving
    cluster), in the order the merging algorithm settled on.
    Pipe through `Color.Palette.sort/2` for a perceptually
    ordered strip.

  ### Examples

      iex> hexes = ["#ff0000", "#fe0202", "#0000ff", "#0202fe", "#00ff00"]
      iex> result = Color.Palette.Summarize.summarize(hexes, 3)
      iex> length(result)
      3

      iex> hexes = ["#ff0000", "#0000ff"]
      iex> Color.Palette.Summarize.summarize(hexes, 5) |> length()
      2

  """
  @spec summarize(list(Color.input()), pos_integer(), keyword()) :: list(Color.SRGB.t())
  def summarize(colors, k, options \\ [])
      when is_list(colors) and is_integer(k) and k > 0 do
    validate_keys!(options)

    cluster_opts = Keyword.take(options, [:ab_weight, :rep_chroma_threshold])
    from_colors_opts = Keyword.take(options, [:weights])

    # Always route through Cluster.merge_until and
    # Cluster.representative even when no merging is needed, so
    # invalid `:ab_weight` / `:rep_chroma_threshold` options are
    # caught regardless of whether the input list happens to be
    # short. `merge_until/3` is a no-op when the input is already
    # at or below the target count.
    if colors == [] do
      []
    else
      colors
      |> Cluster.from_colors(from_colors_opts)
      |> Cluster.merge_until(k, cluster_opts)
      |> Enum.map(&Cluster.representative(&1, cluster_opts))
    end
  end

  defp validate_keys!(options) do
    Enum.each(Keyword.keys(options), fn key ->
      unless key in @valid_keys do
        raise Color.PaletteError,
          reason: :unknown_option,
          detail: "#{inspect(key)} (valid options: #{inspect(@valid_keys)})"
      end
    end)
  end
end
