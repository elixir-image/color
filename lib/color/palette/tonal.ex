defmodule Color.Palette.Tonal do
  @moduledoc """
  A **tonal scale** — N shades of one hue, from light to dark —
  generated from a single seed colour.

  This is the algorithm behind Tailwind's `blue-50` … `blue-950`,
  Radix's 12-step scales, Open Color, and the per-role tonal
  palettes inside Material Design 3.

  ## Algorithm

  1. Convert the seed to **Oklch**.

  2. For each requested stop, compute a target lightness `L` by
     interpolating along a curve between `light_anchor` (the
     lightness of the lightest stop) and `dark_anchor` (the
     lightness of the darkest stop). The interpolation is in
     stop-space — equally spaced positions in the stop list map
     to equally spaced lightnesses.

  3. **Damp the chroma** at the extremes. Tints near white and
     shades near black cannot carry as much chroma as a mid-tone
     of the same hue without falling out of the sRGB gamut. The
     library multiplies the seed's chroma by `sin(π · L)` to taper
     it smoothly toward zero at `L = 0` and `L = 1`.

  4. Optionally apply **hue drift**. When `hue_drift: true`, the
     hue rotates slightly toward yellow (~90°) at the light end
     and toward blue (~270°) at the dark end. This matches how
     human vision perceives lightness — a phenomenon known as the
     Hunt effect — and gives the scale a more natural feel.

  5. **Snap to seed**. Find the generated stop whose lightness is
     closest to the seed's lightness and replace it with the seed
     itself. The `:seed_stop` field on the resulting struct
     records which stop received the seed.

  6. **Gamut-map** each stop into the requested working space
     (default `:SRGB`) using the CSS Color 4 Oklch binary-search
     algorithm provided by `Color.Gamut.to_gamut/3`.

  ## Stops

  By default the stops are Tailwind's `[50, 100, 200, …, 950]`,
  but any list of integer or atom labels may be supplied. The
  algorithm cares only about position in the list, not the label
  values themselves — `["lightest", "light", "mid", "dark",
  "darkest"]` works just as well.

  ## Example

      iex> palette = Color.Palette.Tonal.new("#3b82f6")
      iex> Map.fetch!(palette.stops, 50) |> Color.to_hex()
      "#f4f9ff"

      iex> palette = Color.Palette.Tonal.new("#3b82f6")
      iex> Map.fetch!(palette.stops, 950) |> Color.to_hex()
      "#000825"

  """

  @default_stops [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]
  @default_light_anchor 0.98
  @default_dark_anchor 0.15
  @hue_drift_light 90.0
  @hue_drift_dark 270.0
  @hue_drift_amount 8.0

  defstruct [
    :name,
    :seed,
    :seed_stop,
    :stops,
    :options
  ]

  @type stop_label :: integer() | atom() | binary()

  @type t :: %__MODULE__{
          name: binary() | nil,
          seed: Color.SRGB.t(),
          seed_stop: stop_label(),
          stops: %{stop_label() => Color.SRGB.t()},
          options: keyword()
        }

  @doc """
  Generates a tonal scale from a seed colour.

  See the moduledoc for a description of the algorithm and
  `Color.Palette.tonal/2` for option details.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1`.

  ### Options

  See `Color.Palette.tonal/2`.

  ### Returns

  * A `Color.Palette.Tonal` struct.

  ### Examples

      iex> palette = Color.Palette.Tonal.new("#3b82f6", name: "brand")
      iex> palette.name
      "brand"
      iex> palette.seed_stop in [400, 500]
      true

  """
  @spec new(Color.input(), keyword()) :: t()
  def new(seed, options \\ []) do
    options = validate_options!(options)

    {:ok, seed_srgb} = Color.new(seed)
    {:ok, seed_oklch} = Color.convert(seed_srgb, Color.Oklch)

    stops = Keyword.fetch!(options, :stops)
    light_anchor = Keyword.fetch!(options, :light_anchor)
    dark_anchor = Keyword.fetch!(options, :dark_anchor)
    hue_drift? = Keyword.fetch!(options, :hue_drift)
    gamut = Keyword.fetch!(options, :gamut)

    base_h = seed_oklch.h || 0.0
    base_c = seed_oklch.c || 0.0

    # Generate one Oklch struct per stop, then gamut-map.
    generated =
      stops
      |> Enum.with_index()
      |> Enum.map(fn {label, index} ->
        position = position_for(index, length(stops))
        l = lerp(light_anchor, dark_anchor, position)
        c = base_c * chroma_damping(l)
        h = if hue_drift?, do: drift_hue(base_h, position), else: base_h

        oklch = %Color.Oklch{l: l, c: c, h: h, alpha: seed_srgb.alpha}
        {:ok, mapped} = Color.Gamut.to_gamut(oklch, gamut)
        {label, mapped, l}
      end)

    seed_l = seed_oklch.l || 0.5
    seed_stop_label = nearest_stop(generated, seed_l)

    stops_map =
      Enum.into(generated, %{}, fn
        {^seed_stop_label, _mapped, _l} -> {seed_stop_label, seed_srgb}
        {label, mapped, _l} -> {label, mapped}
      end)

    %__MODULE__{
      name: Keyword.get(options, :name),
      seed: seed_srgb,
      seed_stop: seed_stop_label,
      stops: stops_map,
      options: options
    }
  end

  @doc """
  Fetches the colour at a given stop label.

  ### Arguments

  * `palette` is a `Color.Palette.Tonal` struct.

  * `label` is the stop label to look up.

  ### Returns

  * `{:ok, color}` on success, `:error` if the label is unknown.

  ### Examples

      iex> palette = Color.Palette.Tonal.new("#3b82f6")
      iex> {:ok, _color} = Color.Palette.Tonal.fetch(palette, 500)
      iex> Color.Palette.Tonal.fetch(palette, :missing)
      :error

  """
  @spec fetch(t(), stop_label()) :: {:ok, Color.SRGB.t()} | :error
  def fetch(%__MODULE__{stops: stops}, label), do: Map.fetch(stops, label)

  @doc """
  Returns the list of stop labels in generation order.

  ### Arguments

  * `palette` is a `Color.Palette.Tonal` struct.

  ### Returns

  * A list of stop labels.

  ### Examples

      iex> palette = Color.Palette.Tonal.new("#3b82f6")
      iex> Color.Palette.Tonal.labels(palette)
      [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

  """
  @spec labels(t()) :: [stop_label()]
  def labels(%__MODULE__{options: options}), do: Keyword.fetch!(options, :stops)

  # ---- algorithm helpers --------------------------------------------------

  # Position of stop `index` in `[0, 1]` along the light-to-dark
  # axis. With one stop we put it at the midpoint.
  defp position_for(_index, 1), do: 0.5
  defp position_for(index, count), do: index / (count - 1)

  defp lerp(a, b, t), do: a + (b - a) * t

  # sin(π · L): zero at L = 0 and L = 1, peaks at L = 0.5. Tapers
  # chroma toward white and black so light tints don't look muddy
  # and dark shades don't blow past the sRGB gamut.
  defp chroma_damping(l), do: :math.sin(:math.pi() * clamp01(l))

  # Drift hue toward yellow at the light end and toward blue at
  # the dark end. The drift amount is small (a few degrees) and
  # scales with distance from the midpoint.
  defp drift_hue(h, position) do
    # signed offset in [-1, 1]: -1 = lightest, +1 = darkest.
    delta = (position - 0.5) * 2

    target =
      if delta < 0, do: @hue_drift_light, else: @hue_drift_dark

    # Shortest-path rotation from h toward target, scaled by
    # |delta| · @hue_drift_amount.
    diff = shortest_hue_diff(h, target)
    new_h = h + diff * abs(delta) * (@hue_drift_amount / 180.0)
    wrap_hue(new_h)
  end

  defp shortest_hue_diff(from, to) do
    raw = to - from

    cond do
      raw > 180.0 -> raw - 360.0
      raw < -180.0 -> raw + 360.0
      true -> raw
    end
  end

  defp wrap_hue(h) when h < 0.0, do: wrap_hue(h + 360.0)
  defp wrap_hue(h) when h >= 360.0, do: wrap_hue(h - 360.0)
  defp wrap_hue(h), do: h

  defp clamp01(v) when v < 0.0, do: 0.0
  defp clamp01(v) when v > 1.0, do: 1.0
  defp clamp01(v), do: v

  defp nearest_stop(generated, target_l) do
    {label, _mapped, _l} =
      Enum.min_by(generated, fn {_label, _mapped, l} -> abs(l - target_l) end)

    label
  end

  # ---- options validation -------------------------------------------------

  @valid_keys [:stops, :light_anchor, :dark_anchor, :hue_drift, :gamut, :name]

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
      |> Keyword.put_new(:stops, @default_stops)
      |> Keyword.put_new(:light_anchor, @default_light_anchor)
      |> Keyword.put_new(:dark_anchor, @default_dark_anchor)
      |> Keyword.put_new(:hue_drift, false)
      |> Keyword.put_new(:gamut, :SRGB)

    stops = Keyword.fetch!(options, :stops)

    cond do
      not is_list(stops) ->
        raise Color.PaletteError,
          reason: :invalid_stops,
          detail: ":stops must be a list"

      stops == [] ->
        raise Color.PaletteError,
          reason: :empty_stops,
          detail: ":stops must contain at least one label"

      length(Enum.uniq(stops)) != length(stops) ->
        raise Color.PaletteError,
          reason: :duplicate_stops,
          detail: ":stops must not contain duplicates"

      true ->
        :ok
    end

    light = Keyword.fetch!(options, :light_anchor)
    dark = Keyword.fetch!(options, :dark_anchor)

    unless is_number(light) and light >= 0.0 and light <= 1.0 do
      raise Color.PaletteError,
        reason: :invalid_anchor,
        detail: ":light_anchor must be a number in [0.0, 1.0]"
    end

    unless is_number(dark) and dark >= 0.0 and dark <= 1.0 do
      raise Color.PaletteError,
        reason: :invalid_anchor,
        detail: ":dark_anchor must be a number in [0.0, 1.0]"
    end

    unless light > dark do
      raise Color.PaletteError,
        reason: :invalid_anchor,
        detail: ":light_anchor (#{light}) must be greater than :dark_anchor (#{dark})"
    end

    options
  end
end
