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

  * `:material_pbr` — splits `%Color.Material{}` inputs into
    dielectric and metallic buckets first, then applies hue +
    lightness ordering within each bucket, with roughness as a
    final tiebreaker. Plain colour inputs are treated as
    dielectrics with default roughness. The right choice for
    palettes that mix plastic and metal finishes.

  All strategies operate in Oklch internally (perceptually uniform
  hue and lightness axes). `%Color.Material{}` inputs are
  returned as `%Color.Material{}` structs; other inputs are
  returned as `%Color.SRGB{}`.

  """

  @default_strategy :hue_lightness
  @default_chroma_threshold 0.02
  @default_hue_origin 0.0
  @default_buckets 8
  @default_grays :before
  @default_metallic_threshold 0.5
  @default_metals :after
  @default_roughness_order :glossy_first

  @valid_strategies [:hue_lightness, :stepped_hue, :lightness, :material_pbr]
  @valid_grays [:before, :after, :exclude]
  @valid_metals [:before, :after]
  @valid_roughness_orders [:glossy_first, :matte_first]
  @valid_keys [
    :strategy,
    :chroma_threshold,
    :hue_origin,
    :buckets,
    :grays,
    :metallic_threshold,
    :metals,
    :roughness_order
  ]

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

  * `:metallic_threshold` is the cutoff between dielectric and
    metallic materials in `(0.0, 1.0]`. Default `0.5`. A material
    with `metallic >= threshold` sorts into the metals bucket;
    below goes into dielectrics. Applies to `:material_pbr` only.

  * `:metals` controls whether the metallic bucket comes
    `:before` or `:after` the dielectric bucket. Default
    `:after`, matching typical PBR asset-browser layouts
    (plastics first, metals second). Applies to `:material_pbr`
    only.

  * `:roughness_order` is the tiebreaker direction when two
    otherwise-equal materials differ only in roughness.
    `:glossy_first` (default) puts low-roughness materials first;
    `:matte_first` reverses. Applies to `:material_pbr` only.

  ### Returns

  * A list of `%Color.SRGB{}` structs in sorted order.

  ### Material-aware order (`:material_pbr`)

  When the input mixes `%Color.Material{}` structs (plastic,
  metal, varnish, ceramic), a flat colour sort puts a red
  plastic next to a red-anodized metal — visually the same hue
  but categorically different finishes. `:material_pbr` respects
  the finish cliff by sorting as a tuple:

  1. **Dielectric vs metallic** — split by `metallic >=
     metallic_threshold`. Dielectrics go before metals by
     default (`:metals` option to flip).

  2. **Hue, then lightness** — within each bucket, apply the
     `:hue_lightness` logic on the material's base colour.
     Near-gray materials form their own sub-bucket within each
     metallic group.

  3. **Roughness tiebreaker** — when materials tie on hue and
     lightness (e.g., gloss-red vs matte-red), order by
     roughness. `:glossy_first` (default) puts mirrors before
     matte; `:matte_first` reverses.

  Plain colour inputs (hex strings, `%Color.SRGB{}` structs,
  etc.) are treated as implicit dielectrics with `roughness = 0.5`.
  A mixed list of materials and plain colours sorts them
  together into the dielectric bucket.

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

      iex> items = [
      ...>   Color.Material.new("#ffd700", metallic: 1.0, roughness: 0.05, name: "gold"),
      ...>   Color.Material.new("#ff0000", metallic: 0.0, roughness: 0.6, name: "red plastic")
      ...> ]
      iex> items
      ...> |> Color.Palette.Sort.sort(strategy: :material_pbr)
      ...> |> Enum.map(& &1.name)
      ["red plastic", "gold"]

  """
  @spec sort(list(Color.input()), keyword()) :: list(Color.SRGB.t())
  def sort(colors, options \\ []) when is_list(colors) do
    options = validate_options!(options)

    strategy = Keyword.fetch!(options, :strategy)
    chroma_threshold = Keyword.fetch!(options, :chroma_threshold)
    hue_origin = Keyword.fetch!(options, :hue_origin)
    grays = Keyword.fetch!(options, :grays)
    buckets = Keyword.fetch!(options, :buckets)
    metallic_threshold = Keyword.fetch!(options, :metallic_threshold)
    metals = Keyword.fetch!(options, :metals)
    roughness_order = Keyword.fetch!(options, :roughness_order)

    prepared = Enum.map(colors, &prepare/1)

    case strategy do
      :hue_lightness ->
        sort_hue_lightness(prepared, hue_origin, chroma_threshold, grays)

      :stepped_hue ->
        sort_stepped_hue(prepared, hue_origin, chroma_threshold, grays, buckets)

      :lightness ->
        sort_lightness(prepared)

      :material_pbr ->
        sort_material_pbr(
          prepared,
          hue_origin,
          chroma_threshold,
          grays,
          metallic_threshold,
          metals,
          roughness_order
        )
    end
  end

  # ---- strategies ---------------------------------------------------------

  defp sort_hue_lightness(prepared, hue_origin, chroma_threshold, grays) do
    {gray_items, chromatic_items} = partition_grays(prepared, chroma_threshold)

    sorted_grays = Enum.sort_by(gray_items, & &1.oklch.l)

    sorted_chromatics =
      Enum.sort_by(chromatic_items, fn item ->
        {normalised_hue(item.oklch.h, hue_origin), item.oklch.l}
      end)

    assemble(sorted_grays, sorted_chromatics, grays)
  end

  defp sort_stepped_hue(prepared, hue_origin, chroma_threshold, grays, buckets) do
    {gray_items, chromatic_items} = partition_grays(prepared, chroma_threshold)

    sorted_grays = Enum.sort_by(gray_items, & &1.oklch.l)

    bucket_size = 360.0 / buckets

    grouped =
      Enum.group_by(chromatic_items, fn item ->
        offset = normalised_hue(item.oklch.h, hue_origin)
        # Clamp to last bucket in case of floating-point edge case at 360°.
        min(trunc(offset / bucket_size), buckets - 1)
      end)

    sorted_chromatics =
      Enum.flat_map(0..(buckets - 1), fn bucket_idx ->
        bucket_items =
          grouped
          |> Map.get(bucket_idx, [])
          |> Enum.sort_by(& &1.oklch.l)

        if rem(bucket_idx, 2) == 0, do: bucket_items, else: Enum.reverse(bucket_items)
      end)

    assemble(sorted_grays, sorted_chromatics, grays)
  end

  defp sort_lightness(prepared) do
    prepared
    |> Enum.sort_by(& &1.oklch.l)
    |> Enum.map(& &1.output)
  end

  defp sort_material_pbr(
         prepared,
         hue_origin,
         chroma_threshold,
         grays,
         metallic_threshold,
         metals,
         roughness_order
       ) do
    # Split by metallic bucket first — this is the cliff users
    # perceive most strongly (plastic vs metal).
    {metal_items, dielectric_items} =
      Enum.split_with(prepared, fn item -> item.metallic >= metallic_threshold end)

    dielectric_sorted =
      sort_within_material_bucket(
        dielectric_items,
        hue_origin,
        chroma_threshold,
        grays,
        roughness_order
      )

    metal_sorted =
      sort_within_material_bucket(
        metal_items,
        hue_origin,
        chroma_threshold,
        grays,
        roughness_order
      )

    ordered =
      case metals do
        :after -> dielectric_sorted ++ metal_sorted
        :before -> metal_sorted ++ dielectric_sorted
      end

    Enum.map(ordered, & &1.output)
  end

  # Within a single metallic bucket, apply the hue-lightness
  # logic on the base colour with roughness as the final
  # tiebreaker. Returns the items still wrapped so that the
  # caller controls bucket concatenation and output extraction.
  defp sort_within_material_bucket(items, hue_origin, chroma_threshold, grays, roughness_order) do
    {gray_items, chromatic_items} = partition_grays(items, chroma_threshold)

    sorted_grays =
      Enum.sort_by(gray_items, fn item ->
        {item.oklch.l, roughness_key(item.roughness, roughness_order)}
      end)

    sorted_chromatics =
      Enum.sort_by(chromatic_items, fn item ->
        {
          normalised_hue(item.oklch.h, hue_origin),
          item.oklch.l,
          roughness_key(item.roughness, roughness_order)
        }
      end)

    case grays do
      :before -> sorted_grays ++ sorted_chromatics
      :after -> sorted_chromatics ++ sorted_grays
      :exclude -> sorted_chromatics
    end
  end

  defp roughness_key(roughness, :glossy_first), do: roughness
  defp roughness_key(roughness, :matte_first), do: -roughness

  # ---- helpers ------------------------------------------------------------

  # A `%Color.Material{}` input carries its own metallic and
  # roughness values and must be echoed back in the output.
  defp prepare(%Color.Material{} = material) do
    {:ok, oklch} = Color.convert(material.base_color, Color.Oklch)
    oklch = normalise_oklch(oklch)

    %{
      output: material,
      srgb: material.base_color,
      oklch: oklch,
      metallic: material.metallic,
      roughness: material.roughness
    }
  end

  # Plain colour inputs become implicit dielectrics with
  # roughness 0.5 (so a mixed list of materials and plain
  # colours sorts the plain colours among the dielectrics in a
  # reasonable position).
  defp prepare(input) do
    {:ok, srgb} = Color.new(input)
    {:ok, oklch} = Color.convert(srgb, Color.Oklch)

    %{
      output: srgb,
      srgb: srgb,
      oklch: normalise_oklch(oklch),
      metallic: 0.0,
      roughness: 0.5
    }
  end

  # Oklch's :l, :c, :h can be nil in degenerate cases (e.g.,
  # pure black). Coerce so the sort keys are always numeric.
  defp normalise_oklch(oklch) do
    %{oklch | l: oklch.l || 0.0, c: oklch.c || 0.0, h: oklch.h || 0.0}
  end

  defp partition_grays(prepared, chroma_threshold) do
    Enum.split_with(prepared, fn item -> item.oklch.c < chroma_threshold end)
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
    |> Enum.map(& &1.output)
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
      |> Keyword.put_new(:metallic_threshold, @default_metallic_threshold)
      |> Keyword.put_new(:metals, @default_metals)
      |> Keyword.put_new(:roughness_order, @default_roughness_order)

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

    metallic_threshold = Keyword.fetch!(options, :metallic_threshold)

    unless is_number(metallic_threshold) and metallic_threshold > 0.0 and
             metallic_threshold <= 1.0 do
      raise Color.PaletteError,
        reason: :invalid_metallic_threshold,
        detail: ":metallic_threshold must be a number in (0.0, 1.0]"
    end

    metals = Keyword.fetch!(options, :metals)

    unless metals in @valid_metals do
      raise Color.PaletteError,
        reason: :invalid_metals,
        detail: "#{inspect(metals)} (valid values: #{inspect(@valid_metals)})"
    end

    roughness_order = Keyword.fetch!(options, :roughness_order)

    unless roughness_order in @valid_roughness_orders do
      raise Color.PaletteError,
        reason: :invalid_roughness_order,
        detail: "#{inspect(roughness_order)} (valid values: #{inspect(@valid_roughness_orders)})"
    end

    options
  end
end
