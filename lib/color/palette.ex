defmodule Color.Palette do
  @moduledoc """
  Palette generation for design systems and web sites.

  This module is the public façade for several palette-generation
  algorithms. Each algorithm lives in its own submodule and returns
  a struct with the generated colours and the parameters that
  produced them.

  ## Algorithms

  * `tonal/2` — a single tonal scale (Tailwind / Radix / Open Color
    style) — one seed colour, N shades from light to dark, useful
    for `bg-primary-50` through `bg-primary-950` design tokens.

  * `theme/2` — a complete Material Design 3 style theme from one
    seed: five coordinated tonal scales (primary, secondary,
    tertiary, neutral, neutral-variant), addressable by Material
    role names like `:on_primary` or `:surface_variant`.

  * `contrast/2` — a contrast-targeted palette (Adobe Leonardo
    style) — shades that hit specific WCAG or APCA contrast
    ratios against a chosen background. Use this when you need
    accessibility-guaranteed component states.

  * `contrast_scale/2` — a **contrast-constrained tonal scale**
    (Matt Ström-Awn's approach) — a numbered scale where any
    two stops ≥ `apart` label units apart are guaranteed to
    satisfy a minimum contrast ratio. A hybrid between `tonal`
    and `contrast`.

  * `sort/2` — orders an arbitrary list of colours into a
    perceptually-sensible sequence (rainbow, stepped-hue grid,
    lightness ramp, or material-aware PBR order). Useful when
    you have a heterogeneous bag of swatches and need a
    human-readable layout. When the input mixes
    `%Color.Material{}` structs (plastic, metal, ceramic), the
    `:material_pbr` strategy splits dielectrics from metals
    before colour-sorting each bucket.

  ## Working space

  All palette algorithms operate in **Oklch**, the cylindrical
  variant of Oklab. Oklch is perceptually uniform for lightness,
  which is exactly what tonal scales need: equal lightness steps
  look like equal lightness steps to the eye. After generation,
  each stop is gamut-mapped to sRGB via `Color.Gamut.to_gamut/3`
  using the CSS Color 4 algorithm so that no stop ever falls
  outside the displayable cube.

  """

  alias Color.Palette.Contrast
  alias Color.Palette.ContrastScale
  alias Color.Palette.Sort
  alias Color.Palette.Theme
  alias Color.Palette.Tonal

  @doc """
  Generates a tonal scale — N shades of a single hue — from a seed
  colour. See `Color.Palette.Tonal` for the full algorithm.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1` — a hex string,
    a CSS named colour, an `%Color.SRGB{}` struct, etc.

  ### Options

  * `:stops` is the list of stop labels to generate, default
    `[50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]`
    (Tailwind's convention).

  * `:light_anchor` is the Oklch lightness of the lightest stop,
    default `0.98`.

  * `:dark_anchor` is the Oklch lightness of the darkest stop,
    default `0.15`.

  * `:hue_drift` — when `true`, the hue drifts slightly toward
    yellow at the light end and toward blue at the dark end,
    matching how human vision perceives lightness. Default `false`.

  * `:gamut` is the working space to gamut-map each stop into,
    default `:SRGB`. Widening the gamut (for example `:P3_D65` or
    `:Rec2020`) gives non-seed stops more chroma headroom and
    produces a smoother ramp for saturated seeds, at the cost of
    colours that may not display accurately on sRGB-only monitors.

  * `:chroma_ceiling` is a float in `(0.0, 1.0]` that caps each
    stop's chroma at `ceiling × max_chroma(L, H, gamut)`. The
    default `1.0` lets stops hug the gamut boundary. Lowering it
    (for example `0.85`) produces a more muted, evenly
    saturated-looking ramp.

  * `:name` is an optional string label stored on the struct.

  ### Returns

  * A `Color.Palette.Tonal` struct.

  ### Examples

      iex> palette = Color.Palette.tonal("#3b82f6", name: "blue")
      iex> palette.name
      "blue"
      iex> Map.keys(palette.stops) |> Enum.sort()
      [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

  """
  @spec tonal(Color.input(), keyword()) :: Tonal.t()
  def tonal(seed, options \\ []), do: Tonal.new(seed, options)

  @doc """
  Generates a complete Material Design 3 style theme from a seed
  colour. See `Color.Palette.Theme` for the full algorithm and
  option list.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1`.

  ### Options

  See `Color.Palette.Theme.new/2`.

  ### Returns

  * A `Color.Palette.Theme` struct.

  ### Examples

      iex> theme = Color.Palette.theme("#3b82f6")
      iex> match?(%Color.Palette.Theme{}, theme)
      true

  """
  @spec theme(Color.input(), keyword()) :: Theme.t()
  def theme(seed, options \\ []), do: Theme.new(seed, options)

  @doc """
  Generates a contrast-targeted palette — shades whose contrast
  against a chosen background matches a list of target ratios.
  See `Color.Palette.Contrast` for the full algorithm and option
  list.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1`.

  ### Options

  See `Color.Palette.Contrast.new/2`.

  ### Returns

  * A `Color.Palette.Contrast` struct.

  ### Examples

      iex> palette = Color.Palette.contrast("#3b82f6", targets: [4.5, 7.0])
      iex> length(palette.stops)
      2

  """
  @spec contrast(Color.input(), keyword()) :: Contrast.t()
  def contrast(seed, options \\ []), do: Contrast.new(seed, options)

  @doc """
  Generates a contrast-constrained tonal scale. See
  `Color.Palette.ContrastScale` for the full algorithm.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1`.

  ### Options

  See `Color.Palette.ContrastScale.new/2`.

  ### Returns

  * A `Color.Palette.ContrastScale` struct.

  ### Examples

      iex> palette = Color.Palette.contrast_scale("#3b82f6")
      iex> Map.keys(palette.stops) |> Enum.sort()
      [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

  """
  @spec contrast_scale(Color.input(), keyword()) :: ContrastScale.t()
  def contrast_scale(seed, options \\ []), do: ContrastScale.new(seed, options)

  @doc """
  Sorts a list of colours into a perceptually-ordered sequence.

  Thin wrapper around `Color.Palette.Sort.sort/2`. See that
  module for the full option list and a detailed description of
  each strategy.

  ### Arguments

  * `colors` is a list of values accepted by `Color.new/1`.

  ### Options

  See `Color.Palette.Sort.sort/2`.

  ### Returns

  * A list of `%Color.SRGB{}` structs in sorted order.

  ### Examples

      iex> hexes = ["#808080", "#ff0000", "#00ff00", "#0000ff"]
      iex> hexes |> Color.Palette.sort() |> Enum.map(&Color.to_hex/1)
      ["#808080", "#ff0000", "#00ff00", "#0000ff"]

  """
  @spec sort(list(Color.input()), keyword()) :: list(Color.SRGB.t())
  def sort(colors, options \\ []), do: Sort.sort(colors, options)

  @doc """
  Returns `true` if every stop in the given palette is inside
  the chosen RGB working space.

  Dispatches on the palette struct type, so works uniformly for
  `Color.Palette.Tonal`, `Color.Palette.Theme`,
  `Color.Palette.Contrast`, and `Color.Palette.ContrastScale`.

  Intended primarily for CI checks — call once per palette and
  fail the build if the result is `false`.

  ### Arguments

  * `palette` is any palette struct produced by this module.

  * `working_space` is an RGB working-space atom. Defaults to
    `:SRGB`.

  ### Returns

  * A boolean.

  ### Examples

      iex> palette = Color.Palette.tonal("#3b82f6")
      iex> Color.Palette.in_gamut?(palette)
      true

      iex> theme = Color.Palette.theme("#3b82f6")
      iex> Color.Palette.in_gamut?(theme, :SRGB)
      true

  """
  @spec in_gamut?(struct(), Color.Types.working_space()) :: boolean()
  def in_gamut?(palette, working_space \\ :SRGB)
  def in_gamut?(%Tonal{} = p, ws), do: Tonal.in_gamut?(p, ws)
  def in_gamut?(%Theme{} = p, ws), do: Theme.in_gamut?(p, ws)
  def in_gamut?(%Contrast{} = p, ws), do: Contrast.in_gamut?(p, ws)
  def in_gamut?(%ContrastScale{} = p, ws), do: ContrastScale.in_gamut?(p, ws)

  @doc """
  Returns a detailed gamut report on the given palette.

  Dispatches on palette type — see each palette module's
  `gamut_report/2` for the returned map's exact shape.

  ### Arguments

  * `palette` is any palette struct produced by this module.

  * `working_space` defaults to `:SRGB`.

  ### Returns

  * A map. The top-level `:in_gamut?` key is present on every
    palette type.

  ### Examples

      iex> palette = Color.Palette.tonal("#3b82f6")
      iex> report = Color.Palette.gamut_report(palette, :SRGB)
      iex> report.in_gamut?
      true

  """
  @spec gamut_report(struct(), Color.Types.working_space()) :: map()
  def gamut_report(palette, working_space \\ :SRGB)
  def gamut_report(%Tonal{} = p, ws), do: Tonal.gamut_report(p, ws)
  def gamut_report(%Theme{} = p, ws), do: Theme.gamut_report(p, ws)
  def gamut_report(%Contrast{} = p, ws), do: Contrast.gamut_report(p, ws)
  def gamut_report(%ContrastScale{} = p, ws), do: ContrastScale.gamut_report(p, ws)

  # ---- semantic colours ----------------------------------------------------

  # Canonical Oklch hue centres for the eight major colour
  # categories. The values come from where each hue's primary
  # lies in Oklch space (red ~25°, green ~145°, blue ~250°, …)
  # — intuitive, evenly spaced, and what most UI palettes treat
  # as "the red" / "the green".
  @hue_centres %{
    red: 25.0,
    orange: 55.0,
    yellow: 95.0,
    green: 145.0,
    teal: 190.0,
    blue: 250.0,
    purple: 305.0,
    pink: 345.0
  }

  # Semantic aliases — the UI vocabulary users actually reach
  # for. Each maps to one of the canonical hue atoms, with the
  # exception of `:neutral` which means "strip almost all chroma
  # from the seed", so it needs special handling.
  @semantic_aliases %{
    success: :green,
    positive: :green,
    danger: :red,
    error: :red,
    destructive: :red,
    warning: :orange,
    caution: :orange,
    info: :blue,
    information: :blue,
    neutral: :neutral
  }

  @doc """
  Generates a colour in the given category while preserving the
  seed's perceived lightness and chroma.

  Useful for synthesising **semantic colours** — success, danger,
  warning, info — that feel like they belong to the same palette
  as a brand seed, without every brand needing hand-picked
  accents.

  The algorithm is deliberately simple: convert the seed to
  Oklch, look up the category's canonical hue (e.g. red ≈ 25°,
  green ≈ 145°, blue ≈ 250°), build an Oklch colour at that hue
  with the seed's lightness and chroma, and gamut-map into sRGB.
  The output's saturation and perceived weight will match the
  seed, just at a different hue.

  Once you have the semantic colour, feed it into
  `tonal/2`, `theme/2`, `contrast/2`, or `contrast_scale/2` to
  produce a full scale for that semantic role.

  ### Supported categories

  **Semantic aliases** (UI vocabulary):

  * `:success`, `:positive` → green
  * `:danger`, `:error`, `:destructive` → red
  * `:warning`, `:caution` → orange
  * `:info`, `:information` → blue
  * `:neutral` → strips almost all chroma, preserving the seed's
    hue as a subtle tint

  **Hue categories** (direct names):

  * `:red`, `:orange`, `:yellow`, `:green`, `:teal`, `:blue`,
    `:purple`, `:pink`

  See `semantic_categories/0` for the authoritative list at
  runtime.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1`.

  * `category` is a semantic alias or hue-category atom (see
    above).

  ### Options

  * `:chroma_factor` multiplies the seed's chroma before the
    output is built. `1.0` (default) preserves it, `0.5` mutes
    the result, `0.0` produces a grey at the new hue.

  * `:lightness` overrides the output's lightness with a value
    in `[0.0, 1.0]` in Oklch. Defaults to the seed's lightness.

  * `:gamut` is the RGB working space to map into. Default
    `:SRGB`.

  ### Returns

  * A colour struct in the chosen gamut (typically
    `%Color.SRGB{}`).

  ### Examples

      iex> {:ok, _} = Color.new("#3b82f6")
      iex> danger = Color.Palette.semantic("#3b82f6", :danger)
      iex> {:ok, oklch} = Color.convert(danger, Color.Oklch)
      iex> oklch.h >= 15 and oklch.h <= 40
      true

      iex> success = Color.Palette.semantic("#3b82f6", :success)
      iex> {:ok, oklch} = Color.convert(success, Color.Oklch)
      iex> oklch.h >= 130 and oklch.h <= 160
      true

      iex> neutral = Color.Palette.semantic("#3b82f6", :neutral)
      iex> {:ok, oklch} = Color.convert(neutral, Color.Oklch)
      iex> oklch.c < 0.05
      true

  """
  @spec semantic(Color.input(), atom(), keyword()) :: struct()
  def semantic(seed, category, options \\ []) do
    resolved = Map.get(@semantic_aliases, category, category)

    case resolved do
      :neutral ->
        build_neutral(seed, options)

      hue_name when is_map_key(@hue_centres, hue_name) ->
        build_at_hue(seed, Map.fetch!(@hue_centres, hue_name), options)

      _ ->
        raise ArgumentError,
              "Unknown semantic category #{inspect(category)}. " <>
                "Known: #{inspect(Enum.sort(semantic_categories()))}"
    end
  end

  @doc """
  Returns the full list of category atoms accepted by
  `semantic/3`.

  ### Returns

  * A list of atoms in alphabetical order.

  ### Examples

      iex> categories = Color.Palette.semantic_categories()
      iex> :success in categories
      true
      iex> :red in categories
      true

  """
  @spec semantic_categories() :: [atom()]
  def semantic_categories do
    (Map.keys(@hue_centres) ++ Map.keys(@semantic_aliases))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp build_at_hue(seed, target_hue, options) do
    {:ok, seed_oklch} = Color.convert(seed, Color.Oklch)
    chroma_factor = Keyword.get(options, :chroma_factor, 1.0)
    lightness = Keyword.get(options, :lightness, seed_oklch.l || 0.5)
    gamut = Keyword.get(options, :gamut, :SRGB)

    base_chroma = seed_oklch.c || 0.0

    oklch = %Color.Oklch{
      l: lightness,
      c: base_chroma * chroma_factor,
      h: target_hue,
      alpha: seed_oklch.alpha
    }

    {:ok, mapped} = Color.Gamut.to_gamut(oklch, gamut)
    mapped
  end

  defp build_neutral(seed, options) do
    {:ok, seed_oklch} = Color.convert(seed, Color.Oklch)
    lightness = Keyword.get(options, :lightness, seed_oklch.l || 0.5)
    gamut = Keyword.get(options, :gamut, :SRGB)

    oklch = %Color.Oklch{
      l: lightness,
      c: 0.02,
      h: seed_oklch.h || 0.0,
      alpha: seed_oklch.alpha
    }

    {:ok, mapped} = Color.Gamut.to_gamut(oklch, gamut)
    mapped
  end
end
