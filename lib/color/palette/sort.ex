defmodule Color.Palette.Sort do
  @moduledoc """
  Sort a list of colours into a perceptually-ordered sequence.

  Useful when you have a heterogeneous bag of colours — brand
  swatches, Material role tokens, extracted image palette, etc. —
  and want to lay them out as a linear strip or grid in an order
  a human will find natural.

  Four strategies are available, each with a different contract:

  * `:hue_lightness` (default) — "rainbow" order: hue first, then
    lightness. Matches the usual user expectation of a ROYGBIV
    ramp when the input spans multiple hues. See `sort/2` for the
    design decisions.

  * `:stepped_hue` — Alan Zucconi's bucketed algorithm. Coarse
    rainbow order at the bucket level, with alternating-direction
    lightness ramps *within* each bucket. Produces visually
    continuous swatch grids at the cost of local non-monotonicity.

  * `:lightness` — dark → light, hue ignored. The right choice
    for sequential legends or contrast demos.

  All strategies operate in Oklch internally (perceptually uniform
  hue and lightness axes) and preserve the caller's input structs
  — only the ordering changes.

  """

  @default_strategy :hue_lightness
  @default_chroma_threshold 0.02
  @default_hue_origin 0.0
  @default_buckets 8
  @default_grays :before

  @valid_strategies [:hue_lightness, :stepped_hue, :lightness]
  @valid_grays [:before, :after, :exclude]
  @valid_keys [:strategy, :chroma_threshold, :hue_origin, :buckets, :grays]

  @doc """
  Sorts a list of colours into a perceptually-ordered sequence.

  ### Arguments

  * `colors` is a list of values accepted by `Color.new/1` — hex
    strings, CSS named colours, `%Color.SRGB{}` structs, Oklch
    structs, etc. Mixed types are allowed.

  ### Options

  * `:strategy` is the sort algorithm. One of `:hue_lightness`
    (default), `:stepped_hue`, or `:lightness`. See the moduledoc
    for a description of each.

  * `:chroma_threshold` is the Oklch chroma below which a colour
    is treated as an achromatic *gray* rather than a chromatic
    hue. Grays are grouped into a separate bucket (see `:grays`)
    because their hue angle is numerically unstable and would
    otherwise scatter them randomly through the rainbow. Default
    `0.02`.

  * `:hue_origin` is the Oklch hue angle (in degrees, 0–360)
    where the rainbow "starts" — that is, where the sort cuts
    the hue circle. Default `0.0` (red/orange region). Set to
    `270.0` to start the rainbow at blue/purple, for example.
    Applies to `:hue_lightness` and `:stepped_hue` only.

  * `:grays` controls where achromatic colours land in the
    output. `:before` (default) places them at the start of the
    list, before the chromatic rainbow. `:after` places them at
    the end. `:exclude` drops them entirely. Applies to
    `:hue_lightness` and `:stepped_hue` only.

  * `:buckets` is the number of hue buckets for `:stepped_hue`.
    Default `8`. Only meaningful for that strategy.

  ### Returns

  * A list of `%Color.SRGB{}` structs in sorted order.

  ### Rainbow order (`:hue_lightness`)

  The default strategy produces a linear rainbow and is worth
  describing precisely because several small decisions affect
  what a user sees.

    1. **Convert to Oklch.** Hue angles come from Oklch, not HSL,
       because Oklch's hue axis is perceptually uniform. In HSL,
       yellow occupies a tiny sliver and green dominates; in
       Oklch the visual spacing of a sorted rainbow matches the
       numerical spacing of the sort.

    2. **Partition by chroma.** Colours with `C < chroma_threshold`
       are considered achromatic. Near-grays have mathematically
       unstable hue (a 0.001 change in chroma can flip the
       angle wildly), so sorting them with the chromatic colours
       scatters them across the rainbow in visually random
       places. The gray bucket is sorted independently by
       lightness and placed at the start (or end, via `:grays`).

    3. **Sort the chromatic bucket.** Primary key is
       `(H - hue_origin) mod 360`, ascending. Secondary key is
       lightness `L`, ascending — so within a single hue, the
       darkest shade comes first. This produces ROYGBIV → wrap
       when `hue_origin = 0`.

    4. **The wraparound caveat.** A hue circle has no start or
       end; the sort has to cut it somewhere. The first and last
       colours in the output are therefore neighbours on the
       hue wheel but visually far apart in a linear strip. This
       is intrinsic to projecting a circle onto a line — pick
       `hue_origin` to put the cut somewhere your input doesn't
       cross, if you can.

    5. **Known surprises.** Brown sits near orange and yellow in
       any hue-based sort (brown is dark orange/yellow); users
       who mentally file brown as its own category will find its
       placement unexpected. Magenta is a non-spectral colour and
       lands adjacent to blue and red in hue-angle space, which
       is topologically correct but may surprise users who
       expect a strict wavelength ordering.

  ### Examples

      iex> hexes = ["#808080", "#ff0000", "#00ff00", "#0000ff", "#ffff00"]
      iex> hexes |> Color.Palette.Sort.sort() |> Enum.map(&Color.to_hex/1)
      ["#808080", "#ff0000", "#ffff00", "#00ff00", "#0000ff"]

      iex> hexes = ["#ff0000", "#ffff00", "#00ff00"]
      iex> hexes |> Color.Palette.Sort.sort(strategy: :lightness) |> Enum.map(&Color.to_hex/1)
      ["#ff0000", "#00ff00", "#ffff00"]

      iex> hexes = ["#ff0000", "#0000ff"]
      iex> hexes |> Color.Palette.Sort.sort(grays: :exclude) |> Enum.map(&Color.to_hex/1)
      ["#ff0000", "#0000ff"]

  """
  @spec sort(list(Color.input()), keyword()) :: list(Color.SRGB.t())
  def sort(colors, options \\ []) when is_list(colors) do
    options = validate_options!(options)

    strategy = Keyword.fetch!(options, :strategy)
    chroma_threshold = Keyword.fetch!(options, :chroma_threshold)
    hue_origin = Keyword.fetch!(options, :hue_origin)
    grays = Keyword.fetch!(options, :grays)
    buckets = Keyword.fetch!(options, :buckets)

    prepared = Enum.map(colors, &prepare/1)

    case strategy do
      :hue_lightness ->
        sort_hue_lightness(prepared, hue_origin, chroma_threshold, grays)

      :stepped_hue ->
        sort_stepped_hue(prepared, hue_origin, chroma_threshold, grays, buckets)

      :lightness ->
        sort_lightness(prepared)
    end
  end

  # ---- strategies ---------------------------------------------------------

  defp sort_hue_lightness(prepared, hue_origin, chroma_threshold, grays) do
    {gray_items, chromatic_items} = partition_grays(prepared, chroma_threshold)

    sorted_grays = Enum.sort_by(gray_items, fn {_srgb, oklch} -> oklch.l end)

    sorted_chromatics =
      Enum.sort_by(chromatic_items, fn {_srgb, oklch} ->
        {normalised_hue(oklch.h, hue_origin), oklch.l}
      end)

    assemble(sorted_grays, sorted_chromatics, grays)
  end

  defp sort_stepped_hue(prepared, hue_origin, chroma_threshold, grays, buckets) do
    {gray_items, chromatic_items} = partition_grays(prepared, chroma_threshold)

    sorted_grays = Enum.sort_by(gray_items, fn {_srgb, oklch} -> oklch.l end)

    bucket_size = 360.0 / buckets

    grouped =
      Enum.group_by(chromatic_items, fn {_srgb, oklch} ->
        offset = normalised_hue(oklch.h, hue_origin)
        # Clamp to last bucket in case of floating-point edge case at 360°.
        min(trunc(offset / bucket_size), buckets - 1)
      end)

    sorted_chromatics =
      Enum.flat_map(0..(buckets - 1), fn bucket_idx ->
        bucket_items =
          grouped
          |> Map.get(bucket_idx, [])
          |> Enum.sort_by(fn {_srgb, oklch} -> oklch.l end)

        if rem(bucket_idx, 2) == 0, do: bucket_items, else: Enum.reverse(bucket_items)
      end)

    assemble(sorted_grays, sorted_chromatics, grays)
  end

  defp sort_lightness(prepared) do
    prepared
    |> Enum.sort_by(fn {_srgb, oklch} -> oklch.l end)
    |> Enum.map(fn {srgb, _oklch} -> srgb end)
  end

  # ---- helpers ------------------------------------------------------------

  defp prepare(input) do
    {:ok, srgb} = Color.new(input)
    {:ok, oklch} = Color.convert(srgb, Color.Oklch)

    # Oklch's :l, :c, :h can be nil in degenerate cases (e.g.,
    # pure black). Coerce so the sort keys are always numeric.
    oklch = %{oklch | l: oklch.l || 0.0, c: oklch.c || 0.0, h: oklch.h || 0.0}

    {srgb, oklch}
  end

  defp partition_grays(prepared, chroma_threshold) do
    Enum.split_with(prepared, fn {_srgb, oklch} -> oklch.c < chroma_threshold end)
  end

  defp normalised_hue(h, hue_origin) do
    :math.fmod(h - hue_origin + 360.0, 360.0)
  end

  defp assemble(grays, chromatics, placement) do
    case placement do
      :before -> grays ++ chromatics
      :after -> chromatics ++ grays
      :exclude -> chromatics
    end
    |> Enum.map(fn {srgb, _oklch} -> srgb end)
  end

  # ---- options validation -------------------------------------------------

  defp validate_options!(options) do
    Enum.each(Keyword.keys(options), fn key ->
      unless key in @valid_keys do
        raise Color.PaletteError,
          reason: :unknown_option,
          detail: "#{inspect(key)} (valid options: #{inspect(@valid_keys)})"
      end
    end)

    options =
      options
      |> Keyword.put_new(:strategy, @default_strategy)
      |> Keyword.put_new(:chroma_threshold, @default_chroma_threshold)
      |> Keyword.put_new(:hue_origin, @default_hue_origin)
      |> Keyword.put_new(:buckets, @default_buckets)
      |> Keyword.put_new(:grays, @default_grays)

    strategy = Keyword.fetch!(options, :strategy)

    unless strategy in @valid_strategies do
      raise Color.PaletteError,
        reason: :invalid_strategy,
        detail: "#{inspect(strategy)} (valid strategies: #{inspect(@valid_strategies)})"
    end

    threshold = Keyword.fetch!(options, :chroma_threshold)

    unless is_number(threshold) and threshold >= 0.0 do
      raise Color.PaletteError,
        reason: :invalid_chroma_threshold,
        detail: ":chroma_threshold must be a non-negative number"
    end

    origin = Keyword.fetch!(options, :hue_origin)

    unless is_number(origin) and origin >= 0.0 and origin < 360.0 do
      raise Color.PaletteError,
        reason: :invalid_hue_origin,
        detail: ":hue_origin must be a number in [0.0, 360.0)"
    end

    buckets = Keyword.fetch!(options, :buckets)

    unless is_integer(buckets) and buckets >= 2 do
      raise Color.PaletteError,
        reason: :invalid_buckets,
        detail: ":buckets must be an integer ≥ 2"
    end

    grays = Keyword.fetch!(options, :grays)

    unless grays in @valid_grays do
      raise Color.PaletteError,
        reason: :invalid_grays,
        detail: "#{inspect(grays)} (valid values: #{inspect(@valid_grays)})"
    end

    options
  end
end
