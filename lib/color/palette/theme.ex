defmodule Color.Palette.Theme do
  @moduledoc """
  A complete **theme** — a coordinated set of five tonal scales —
  generated from a single seed colour.

  Inspired by **Material Design 3** and Material You's dynamic
  theming. From one seed, this module produces five related
  `Color.Palette.Tonal` palettes:

  * `:primary` — the seed's hue at full chroma. The main brand
    colour and the accent for interactive elements.

  * `:secondary` — the seed's hue at reduced chroma (default ⅓).
    A quieter accent for secondary actions.

  * `:tertiary` — the seed's hue rotated by a fixed angle
    (default +60°) at full chroma. A complementary accent.

  * `:neutral` — the seed's hue at very low chroma (default 0.02).
    For surfaces, backgrounds, and text.

  * `:neutral_variant` — the seed's hue at slightly higher chroma
    (default 0.04). For outlines and dividers.

  Each of the five palettes has its own 13-stop tonal scale (or
  whatever stops were configured), so one seed yields ~65 colours
  covering every role a typical component library needs.

  ## Material roles

  `role/2` maps a symbolic role name to a specific stop in one of
  the five palettes, following Material 3's role tokens:

      iex> theme = Color.Palette.Theme.new("#3b82f6")
      iex> {:ok, primary} = Color.Palette.Theme.role(theme, :primary)
      iex> {:ok, on_primary} = Color.Palette.Theme.role(theme, :on_primary)
      iex> match?(%Color.SRGB{}, primary) and match?(%Color.SRGB{}, on_primary)
      true

  """

  alias Color.Palette.Tonal

  @material_stops [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100]

  @default_secondary_chroma_factor 0.33
  @default_tertiary_hue_rotation 60.0
  @default_neutral_chroma 0.02
  @default_neutral_variant_chroma 0.04

  @valid_keys [
    :stops,
    :secondary_chroma_factor,
    :tertiary_hue_rotation,
    :neutral_chroma,
    :neutral_variant_chroma,
    :light_anchor,
    :dark_anchor,
    :hue_drift,
    :gamut,
    :name
  ]

  defstruct [
    :name,
    :seed,
    :primary,
    :secondary,
    :tertiary,
    :neutral,
    :neutral_variant,
    :options
  ]

  @type t :: %__MODULE__{
          name: binary() | nil,
          seed: Color.SRGB.t(),
          primary: Tonal.t(),
          secondary: Tonal.t(),
          tertiary: Tonal.t(),
          neutral: Tonal.t(),
          neutral_variant: Tonal.t(),
          options: keyword()
        }

  # Material 3 role → {palette, stop} for the LIGHT scheme. The
  # DARK scheme flips some of these; we return light by default
  # and expose :scheme as an option on role/3.
  @light_roles %{
    primary: {:primary, 40},
    on_primary: {:primary, 100},
    primary_container: {:primary, 90},
    on_primary_container: {:primary, 10},
    secondary: {:secondary, 40},
    on_secondary: {:secondary, 100},
    secondary_container: {:secondary, 90},
    on_secondary_container: {:secondary, 10},
    tertiary: {:tertiary, 40},
    on_tertiary: {:tertiary, 100},
    tertiary_container: {:tertiary, 90},
    on_tertiary_container: {:tertiary, 10},
    surface: {:neutral, 99},
    on_surface: {:neutral, 10},
    surface_variant: {:neutral_variant, 90},
    on_surface_variant: {:neutral_variant, 30},
    outline: {:neutral_variant, 50},
    outline_variant: {:neutral_variant, 80},
    background: {:neutral, 99},
    on_background: {:neutral, 10}
  }

  @dark_roles %{
    primary: {:primary, 80},
    on_primary: {:primary, 20},
    primary_container: {:primary, 30},
    on_primary_container: {:primary, 90},
    secondary: {:secondary, 80},
    on_secondary: {:secondary, 20},
    secondary_container: {:secondary, 30},
    on_secondary_container: {:secondary, 90},
    tertiary: {:tertiary, 80},
    on_tertiary: {:tertiary, 20},
    tertiary_container: {:tertiary, 30},
    on_tertiary_container: {:tertiary, 90},
    surface: {:neutral, 10},
    on_surface: {:neutral, 90},
    surface_variant: {:neutral_variant, 30},
    on_surface_variant: {:neutral_variant, 80},
    outline: {:neutral_variant, 60},
    outline_variant: {:neutral_variant, 30},
    background: {:neutral, 10},
    on_background: {:neutral, 90}
  }

  @doc """
  Generates a complete theme from a seed colour.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1`.

  ### Options

  * `:stops` — the stop list for each of the five tonal scales.
    Defaults to Material 3's `[0, 10, 20, 30, 40, 50, 60, 70, 80,
    90, 95, 99, 100]`, which is what `role/2` expects. Override
    only if you understand that role lookups may then fail.

  * `:secondary_chroma_factor` — how much to multiply the seed's
    chroma by for the secondary palette. Default `0.33`.

  * `:tertiary_hue_rotation` — how many degrees to rotate the hue
    by for the tertiary palette. Default `60.0`.

  * `:neutral_chroma` — absolute Oklch chroma for the neutral
    scale. Default `0.02`.

  * `:neutral_variant_chroma` — absolute Oklch chroma for the
    neutral-variant scale. Default `0.04`.

  * `:light_anchor`, `:dark_anchor`, `:hue_drift`, `:gamut` —
    passed through to each tonal scale. See
    `Color.Palette.Tonal`.

  * `:name` — optional string label stored on the struct.

  ### Returns

  * A `Color.Palette.Theme` struct.

  ### Examples

      iex> theme = Color.Palette.Theme.new("#3b82f6", name: "brand")
      iex> theme.name
      "brand"
      iex> match?(%Color.Palette.Tonal{}, theme.primary)
      true
      iex> match?(%Color.Palette.Tonal{}, theme.neutral)
      true

  """
  @spec new(Color.input(), keyword()) :: t()
  def new(seed, options \\ []) do
    options = validate_options!(options)

    {:ok, seed_srgb} = Color.new(seed)
    {:ok, seed_oklch} = Color.convert(seed_srgb, Color.Oklch)

    base_h = seed_oklch.h || 0.0
    base_c = seed_oklch.c || 0.0

    secondary_factor = Keyword.fetch!(options, :secondary_chroma_factor)
    tertiary_rotation = Keyword.fetch!(options, :tertiary_hue_rotation)
    neutral_c = Keyword.fetch!(options, :neutral_chroma)
    neutral_variant_c = Keyword.fetch!(options, :neutral_variant_chroma)

    tonal_options =
      options
      |> Keyword.take([:stops, :light_anchor, :dark_anchor, :hue_drift, :gamut])

    primary = Tonal.new(seed_srgb, tonal_options)
    secondary = build_variant(base_h, base_c * secondary_factor, tonal_options)
    tertiary = build_variant(wrap_hue(base_h + tertiary_rotation), base_c, tonal_options)
    neutral = build_variant(base_h, neutral_c, tonal_options)
    neutral_variant = build_variant(base_h, neutral_variant_c, tonal_options)

    %__MODULE__{
      name: Keyword.get(options, :name),
      seed: seed_srgb,
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      neutral: neutral,
      neutral_variant: neutral_variant,
      options: options
    }
  end

  @doc """
  Looks up a Material 3 role name in the theme.

  Roles are the symbolic tokens used by Material components —
  `:primary`, `:on_primary`, `:surface`, `:outline`, etc. Each
  role maps to a specific stop in one of the five palettes.

  ### Arguments

  * `theme` is a `Color.Palette.Theme` struct.

  * `role` is a role atom (see
    [Material 3 tokens](https://m3.material.io/styles/color/roles)).

  ### Options

  * `:scheme` is `:light` (default) or `:dark`. The dark scheme
    uses different stops to maintain contrast against a dark
    background.

  ### Returns

  * `{:ok, %Color.SRGB{}}` for known roles, `:error` for unknown
    roles.

  ### Examples

      iex> theme = Color.Palette.Theme.new("#3b82f6")
      iex> {:ok, %Color.SRGB{}} = Color.Palette.Theme.role(theme, :primary)
      iex> {:ok, %Color.SRGB{}} = Color.Palette.Theme.role(theme, :primary, scheme: :dark)
      iex> Color.Palette.Theme.role(theme, :nonsense)
      :error

  """
  @spec role(t(), atom(), keyword()) :: {:ok, Color.SRGB.t()} | :error
  def role(%__MODULE__{} = theme, role, options \\ []) when is_atom(role) do
    scheme = Keyword.get(options, :scheme, :light)

    roles =
      case scheme do
        :light -> @light_roles
        :dark -> @dark_roles
      end

    with {:ok, {palette_key, stop}} <- Map.fetch(roles, role) do
      palette = Map.fetch!(theme, palette_key)
      Tonal.fetch(palette, stop)
    end
  end

  @doc """
  Returns the list of role names supported by `role/3`.

  ### Returns

  * A sorted list of role atoms.

  ### Examples

      iex> :primary in Color.Palette.Theme.roles()
      true
      iex> :surface in Color.Palette.Theme.roles()
      true

  """
  @spec roles() :: [atom()]
  def roles, do: Map.keys(@light_roles) |> Enum.sort()

  @doc """
  Returns `true` when every stop across all five sub-palettes
  (primary, secondary, tertiary, neutral, neutral-variant) is
  inside the given RGB working space.

  ### Arguments

  * `theme` is a `Color.Palette.Theme` struct.

  * `working_space` is an RGB working-space atom. Defaults to
    `:SRGB`.

  ### Returns

  * A boolean.

  ### Examples

      iex> theme = Color.Palette.Theme.new("#3b82f6")
      iex> Color.Palette.Theme.in_gamut?(theme, :SRGB)
      true

  """
  @spec in_gamut?(t(), Color.Types.working_space()) :: boolean()
  def in_gamut?(%__MODULE__{} = theme, working_space \\ :SRGB) do
    [:primary, :secondary, :tertiary, :neutral, :neutral_variant]
    |> Enum.all?(fn key ->
      Color.Palette.Tonal.in_gamut?(Map.fetch!(theme, key), working_space)
    end)
  end

  @doc """
  Returns a detailed gamut report broken down by sub-palette.

  ### Arguments

  * `theme` is a `Color.Palette.Theme` struct.

  * `working_space` defaults to `:SRGB`.

  ### Returns

  * A map with:

    * `:working_space` — the space checked against.

    * `:in_gamut?` — `true` if every stop in every sub-palette
      is inside.

    * `:sub_palettes` — map of sub-palette key →
      `Color.Palette.Tonal.gamut_report/2` result.

    * `:out_of_gamut` — flat list of `%{sub_palette, label,
      color}` for stops that failed, across every sub-palette.

  ### Examples

      iex> theme = Color.Palette.Theme.new("#3b82f6")
      iex> report = Color.Palette.Theme.gamut_report(theme, :SRGB)
      iex> report.in_gamut?
      true
      iex> Map.keys(report.sub_palettes) |> Enum.sort()
      [:neutral, :neutral_variant, :primary, :secondary, :tertiary]

  """
  @spec gamut_report(t(), Color.Types.working_space()) :: map()
  def gamut_report(%__MODULE__{} = theme, working_space \\ :SRGB) do
    keys = [:primary, :secondary, :tertiary, :neutral, :neutral_variant]

    sub_reports =
      Enum.into(keys, %{}, fn key ->
        report = Color.Palette.Tonal.gamut_report(Map.fetch!(theme, key), working_space)
        {key, report}
      end)

    flattened_out =
      Enum.flat_map(sub_reports, fn {key, report} ->
        Enum.map(report.out_of_gamut, &Map.put(&1, :sub_palette, key))
      end)

    %{
      working_space: working_space,
      in_gamut?: Enum.all?(sub_reports, fn {_, r} -> r.in_gamut? end),
      sub_palettes: sub_reports,
      out_of_gamut: flattened_out
    }
  end

  @doc """
  Emits the theme as a W3C [Design Tokens Community Group](https://www.designtokens.org/)
  token file.

  Produces two top-level groups:

  * `"palette"` — the five tonal scales (primary, secondary,
    tertiary, neutral, neutral-variant), each as a stop-keyed
    group of color tokens.

  * `"role"` — Material 3 role tokens (`primary`, `on_primary`,
    `surface`, etc.) emitted as **DTCG alias tokens** that
    reference the corresponding stop in `"palette"`. Tools that
    resolve aliases will see both the raw palette and the
    semantic vocabulary.

  ### Arguments

  * `theme` is a `Color.Palette.Theme` struct.

  ### Options

  * `:space` is the colour space for emitted stop values. Any
    module accepted by `Color.convert/2`. Default `Color.Oklch`.

  * `:scheme` is `:light` (default) or `:dark`. Controls which
    tone each role aliases to.

  ### Returns

  * A map with `"palette"` and `"role"` keys.

  ### Examples

      iex> theme = Color.Palette.Theme.new("#3b82f6")
      iex> tokens = Color.Palette.Theme.to_tokens(theme)
      iex> tokens["palette"]["primary"]["40"]["$type"]
      "color"
      iex> tokens["role"]["primary"]["$value"]
      "{palette.primary.40}"

  """
  @spec to_tokens(t(), keyword()) :: map()
  def to_tokens(%__MODULE__{} = theme, options \\ []) do
    space = Keyword.get(options, :space, Color.Oklch)
    scheme = Keyword.get(options, :scheme, :light)

    palette_group =
      %{
        "primary" => scale_tokens(theme.primary, space),
        "secondary" => scale_tokens(theme.secondary, space),
        "tertiary" => scale_tokens(theme.tertiary, space),
        "neutral" => scale_tokens(theme.neutral, space),
        "neutral_variant" => scale_tokens(theme.neutral_variant, space)
      }

    roles =
      case scheme do
        :light -> @light_roles
        :dark -> @dark_roles
      end

    role_group =
      Enum.into(roles, %{}, fn {role, {palette_key, stop}} ->
        alias_path = "{palette.#{palette_key}.#{stop}}"
        {Atom.to_string(role), %{"$type" => "color", "$value" => alias_path}}
      end)

    %{"palette" => palette_group, "role" => role_group}
  end

  defp scale_tokens(%Color.Palette.Tonal{} = palette, space) do
    Enum.into(palette.stops, %{}, fn {label, color} ->
      {to_string(label), Color.DesignTokens.encode_token(color, space: space)}
    end)
  end

  # ---- builders -----------------------------------------------------------

  # Build a tonal scale at a specific hue and chroma, by
  # synthesising a mid-tone Oklch seed and handing it to
  # Color.Palette.Tonal. Using Oklch L = 0.5 gives the damping
  # function maximum effect at the midpoint, which is what we
  # want for the scale's derived seed.
  defp build_variant(hue, chroma, tonal_options) do
    {:ok, seed_srgb} =
      Color.Gamut.to_gamut(%Color.Oklch{l: 0.5, c: chroma, h: hue}, :SRGB)

    Tonal.new(seed_srgb, tonal_options)
  end

  defp wrap_hue(h) when h < 0.0, do: wrap_hue(h + 360.0)
  defp wrap_hue(h) when h >= 360.0, do: wrap_hue(h - 360.0)
  defp wrap_hue(h), do: h

  # ---- options validation -------------------------------------------------

  defp validate_options!(options) do
    Enum.each(Keyword.keys(options), fn key ->
      unless key in @valid_keys do
        raise Color.PaletteError,
          reason: :unknown_option,
          detail: "#{inspect(key)} (valid options: #{inspect(@valid_keys)})"
      end
    end)

    options
    |> Keyword.put_new(:stops, @material_stops)
    |> Keyword.put_new(:secondary_chroma_factor, @default_secondary_chroma_factor)
    |> Keyword.put_new(:tertiary_hue_rotation, @default_tertiary_hue_rotation)
    |> Keyword.put_new(:neutral_chroma, @default_neutral_chroma)
    |> Keyword.put_new(:neutral_variant_chroma, @default_neutral_variant_chroma)
  end
end
