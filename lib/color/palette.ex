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
    default `:SRGB`.

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
  defdelegate tonal(seed, options \\ []), to: Tonal, as: :new

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
  defdelegate theme(seed, options \\ []), to: Theme, as: :new

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
  defdelegate contrast(seed, options \\ []), to: Contrast, as: :new

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
  defdelegate contrast_scale(seed, options \\ []), to: ContrastScale, as: :new
end
