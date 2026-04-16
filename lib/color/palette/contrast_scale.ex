defmodule Color.Palette.ContrastScale do
  @moduledoc """
  A **contrast-constrained tonal scale** — the hybrid algorithm
  described by Matt Ström-Awn in
  [*Generating colour palettes with math*](https://mattstromawn.com/writing/generating-color-palettes/).

  The scale is generated so that any two stops whose labels
  differ by at least `apart` are **guaranteed** to satisfy a
  minimum contrast ratio against each other. For example, with
  the default `guarantee: {4.5, 500}`, stops 50 and 600 — or any
  other pair ≥ 500 apart — will contrast ≥ 4.5 : 1 against each
  other against the given background.

  Unlike `Color.Palette.Tonal`, which produces visually-even
  lightness steps with no contrast guarantee, and
  `Color.Palette.Contrast`, which places stops at specific
  contrast targets with no between-stop invariant, this
  algorithm makes **pairwise contrast a structural property of
  the scale**.

  ## Algorithm

  Let `t = apart / (max_label − min_label)` — the fraction of
  the scale that the `apart` distance spans. For each stop with
  normalised position `p ∈ [0, 1]`:

  1. Compute the stop's target **contrast against the
     background**: `C(p) = ratio ^ (p / t)`. This places the
     lightest stop at contrast 1 (equal to background) and the
     darkest at `ratio ^ (1/t)`.

  2. Binary-search Oklch lightness for a colour that achieves
     `C(p)` against the background, holding the seed's hue and
     chroma approximately constant.

  The pairwise invariant falls out of this: for any two stops
  `i, j` with `|p_j − p_i| ≥ t`, `contrast(i, j) = C_j / C_i ≥
  ratio`.

  Hue drift (`hue_drift: true`) applies the paper's
  Bezold-Brücke compensation: `H(p) = H_base + 5 · (1 − p)`.

  ## When to reach for this

  * You want a Tailwind-style numeric scale *and* you want
    pairwise contrast guarantees built in.

  * You're building an accessible design system and you don't
    want to audit individual pairs after the fact.

  * You want light and dark modes to follow the same contrast
    rules by construction — generate the same seed against
    `background: "white"` and `background: "black"` and the
    invariant holds on both.

  For component states tied to specific ratios (resting 3 : 1,
  focus 4.5 : 1, disabled 1.3 : 1), `Color.Palette.Contrast` is
  still the right tool. For purely visual scales with no
  accessibility requirement, `Color.Palette.Tonal` produces
  smoother-looking results.

  ## Example

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6")
      iex> Map.keys(palette.stops) |> Enum.sort()
      [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6")
      iex> {ratio, apart} = palette.guarantee
      iex> {ratio, apart}
      {4.5, 500}

  """

  @default_stops [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]
  @default_guarantee {4.5, 500}
  @default_background "white"
  @default_metric :wcag
  @default_hue_drift false
  @default_gamut :SRGB

  @binary_search_iterations 24
  @valid_keys [:stops, :guarantee, :background, :metric, :hue_drift, :gamut, :name]
  @valid_metrics [:wcag, :apca]

  defstruct [
    :name,
    :seed,
    :seed_stop,
    :background,
    :guarantee,
    :metric,
    :stops,
    :achieved,
    :options
  ]

  @type guarantee :: {number(), number()}
  @type stop_label :: integer() | atom() | binary()

  @type t :: %__MODULE__{
          name: binary() | nil,
          seed: Color.SRGB.t(),
          seed_stop: stop_label(),
          background: Color.SRGB.t(),
          guarantee: guarantee(),
          metric: :wcag | :apca,
          stops: %{stop_label() => Color.SRGB.t()},
          achieved: %{stop_label() => number()},
          options: keyword()
        }

  @doc """
  Generates a contrast-constrained tonal scale.

  See the moduledoc for the algorithm.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1`.

  ### Options

  * `:stops` is the list of numeric stop labels. Default
    `[50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]`.
    The labels **must be numeric** — the contrast invariant is
    defined in terms of label distance.

  * `:guarantee` is a `{ratio, apart}` tuple specifying the
    minimum contrast ratio that any two stops `apart` label units
    apart must satisfy. Default `{4.5, 500}` (WCAG AA body text).

  * `:background` is the colour against which contrast is
    measured. Default `"white"`.

  * `:metric` is `:wcag` (default) or `:apca`. For `:apca`,
    `ratio` is interpreted as an APCA Lc value.

  * `:hue_drift` enables the paper's Bezold-Brücke
    compensation. Default `false`.

  * `:gamut` is the gamut to map each stop into. Default
    `:SRGB`.

  * `:name` is an optional label.

  ### Returns

  * A `Color.Palette.ContrastScale` struct.

  ### Examples

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6", name: "blue")
      iex> palette.name
      "blue"
      iex> palette.seed_stop in Map.keys(palette.stops)
      true

  """
  @spec new(Color.input(), keyword()) :: t()
  def new(seed, options \\ []) do
    options = validate_options!(options)

    stops = Keyword.fetch!(options, :stops)
    {ratio, apart} = Keyword.fetch!(options, :guarantee)
    bg_input = Keyword.fetch!(options, :background)
    metric = Keyword.fetch!(options, :metric)
    hue_drift? = Keyword.fetch!(options, :hue_drift)
    gamut = Keyword.fetch!(options, :gamut)
    name = Keyword.get(options, :name)

    {:ok, seed_srgb} = Color.new(seed)
    {:ok, seed_oklch} = Color.convert(seed_srgb, Color.Oklch)
    {:ok, bg_srgb} = Color.new(bg_input)

    {min_label, max_label} = Enum.min_max(stops)
    range = max(max_label - min_label, 1)
    t = apart / range

    base_h = seed_oklch.h || 0.0
    base_c = seed_oklch.c || 0.0

    computed =
      stops
      |> Enum.map(fn label ->
        pos = (label - min_label) / range
        target = :math.pow(ratio, pos / t)
        hue = if hue_drift?, do: drift_hue(base_h, pos), else: base_h
        {achieved, color} = find_stop(target, hue, base_c, bg_srgb, metric, gamut)
        {label, achieved, color}
      end)

    seed_contrast = measure(seed_srgb, bg_srgb, metric)
    seed_stop_label = nearest_by_contrast(computed, seed_contrast)

    stops_map =
      Enum.into(computed, %{}, fn
        {^seed_stop_label, _a, _c} -> {seed_stop_label, seed_srgb}
        {label, _a, color} -> {label, color}
      end)

    achieved_map =
      Enum.into(computed, %{}, fn
        {^seed_stop_label, _a, _c} -> {seed_stop_label, seed_contrast}
        {label, achieved, _c} -> {label, achieved}
      end)

    %__MODULE__{
      name: name,
      seed: seed_srgb,
      seed_stop: seed_stop_label,
      background: bg_srgb,
      guarantee: {ratio, apart},
      metric: metric,
      stops: stops_map,
      achieved: achieved_map,
      options: options
    }
  end

  @doc """
  Fetches the colour at a given stop label.

  ### Arguments

  * `palette` is a `Color.Palette.ContrastScale` struct.

  * `label` is the stop label.

  ### Returns

  * `{:ok, color}` or `:error` for unknown labels.

  ### Examples

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6")
      iex> {:ok, _} = Color.Palette.ContrastScale.fetch(palette, 500)
      iex> Color.Palette.ContrastScale.fetch(palette, :missing)
      :error

  """
  @spec fetch(t(), stop_label()) :: {:ok, Color.SRGB.t()} | :error
  def fetch(%__MODULE__{stops: stops}, label), do: Map.fetch(stops, label)

  @doc """
  Returns the list of stop labels in the order they were
  configured.

  ### Arguments

  * `palette` is a `Color.Palette.ContrastScale` struct.

  ### Returns

  * A list of stop labels.

  ### Examples

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6")
      iex> Color.Palette.ContrastScale.labels(palette)
      [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

  """
  @spec labels(t()) :: [stop_label()]
  def labels(%__MODULE__{options: options}), do: Keyword.fetch!(options, :stops)

  @doc """
  Emits the palette as a W3C [DTCG](https://www.designtokens.org/tr/2025.10/color/)
  color-token group, with the achieved contrast ratio for each
  stop recorded in `$extensions.color.achieved`.

  ### Arguments

  * `palette` is a `Color.Palette.ContrastScale` struct.

  ### Options

  * `:space` is the colour space for emitted stop values.
    Default `Color.Oklch`.

  * `:name` overrides the group name. Defaults to the palette's
    `:name` field, or `"contrast_scale"` if unset.

  ### Returns

  * A map shaped as `%{"<name>" => %{"<label>" => token, ...}}`.

  ### Examples

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6", name: "blue")
      iex> tokens = Color.Palette.ContrastScale.to_tokens(palette)
      iex> tokens["blue"]["500"]["$type"]
      "color"

  """
  @spec to_tokens(t(), keyword()) :: map()
  def to_tokens(%__MODULE__{} = palette, options \\ []) do
    space = Keyword.get(options, :space, Color.Oklch)
    name = Keyword.get(options, :name, palette.name || "contrast_scale")

    stop_tokens =
      Enum.into(palette.stops, %{}, fn {label, color} ->
        base = Color.DesignTokens.encode_token(color, space: space)
        achieved = Map.get(palette.achieved, label)
        {to_string(label), put_achieved(base, achieved, palette.metric)}
      end)

    %{name => stop_tokens}
  end

  defp put_achieved(token, nil, _metric), do: token

  defp put_achieved(token, achieved, metric) do
    ext =
      token
      |> Map.get("$extensions", %{})
      |> Map.put("color", %{"achieved" => achieved, "metric" => Atom.to_string(metric)})

    Map.put(token, "$extensions", ext)
  end

  @doc """
  Returns `true` when every stop in the palette is inside the
  given RGB working space. See `Color.Palette.Tonal.in_gamut?/2`
  for details.

  ### Examples

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6")
      iex> Color.Palette.ContrastScale.in_gamut?(palette, :SRGB)
      true

  """
  @spec in_gamut?(t(), Color.Types.working_space()) :: boolean()
  def in_gamut?(%__MODULE__{stops: stops}, working_space \\ :SRGB) do
    Enum.all?(stops, fn {_label, color} ->
      Color.Gamut.in_gamut?(color, working_space)
    end)
  end

  @doc """
  Returns a detailed per-stop gamut report. See
  `Color.Palette.Tonal.gamut_report/2` for the shape.

  ### Examples

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6")
      iex> %{in_gamut?: true} = Color.Palette.ContrastScale.gamut_report(palette, :SRGB)

  """
  @spec gamut_report(t(), Color.Types.working_space()) :: map()
  def gamut_report(%__MODULE__{} = palette, working_space \\ :SRGB) do
    stops =
      palette
      |> labels()
      |> Enum.map(fn label ->
        color = Map.fetch!(palette.stops, label)
        in_gamut? = Color.Gamut.in_gamut?(color, working_space)
        %{label: label, color: color, in_gamut?: in_gamut?}
      end)

    %{
      working_space: working_space,
      in_gamut?: Enum.all?(stops, & &1.in_gamut?),
      stops: stops,
      out_of_gamut: Enum.reject(stops, & &1.in_gamut?)
    }
  end

  @doc """
  Emits the palette as a block of **CSS custom properties**. See
  `Color.Palette.Tonal.to_css/2` for option details.

  ### Examples

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6", name: "blue")
      iex> css = Color.Palette.ContrastScale.to_css(palette)
      iex> String.contains?(css, "--blue-500:")
      true

  """
  @spec to_css(t(), keyword()) :: binary()
  def to_css(%__MODULE__{} = palette, options \\ []) do
    name = Keyword.get(options, :name, palette.name || "color")
    selector = Keyword.get(options, :selector, ":root")
    labels = labels(palette)

    body =
      Enum.map_join(labels, "", fn label ->
        color = Map.fetch!(palette.stops, label)
        "  --#{name}-#{label}: #{Color.to_hex(color)};\n"
      end)

    "#{selector} {\n#{body}}\n"
  end

  @doc """
  Emits the palette as a **Tailwind CSS v4 `@theme` block**. See
  `Color.Palette.Tonal.to_tailwind/2` for option details.

  ### Examples

      iex> palette = Color.Palette.ContrastScale.new("#3b82f6", name: "blue")
      iex> tw = Color.Palette.ContrastScale.to_tailwind(palette)
      iex> String.contains?(tw, "--color-blue-500:")
      true

  """
  @spec to_tailwind(t(), keyword()) :: binary()
  def to_tailwind(%__MODULE__{} = palette, options \\ []) do
    name = Keyword.get(options, :name, palette.name || "color")
    labels = labels(palette)

    body =
      Enum.map_join(labels, "", fn label ->
        color = Map.fetch!(palette.stops, label)
        "  --color-#{name}-#{label}: #{Color.to_hex(color)};\n"
      end)

    "@theme {\n#{body}}\n"
  end

  # ---- algorithm ----------------------------------------------------------

  # Bezold-Brücke: H(p) = H_base + 5 · (1 − p). Small drift toward
  # yellow at the light end. Matches the paper's formula exactly.
  defp drift_hue(h, pos) do
    shifted = h + 5.0 * (1.0 - pos)
    wrap_hue(shifted)
  end

  defp wrap_hue(h) when h < 0.0, do: wrap_hue(h + 360.0)
  defp wrap_hue(h) when h >= 360.0, do: wrap_hue(h - 360.0)
  defp wrap_hue(h), do: h

  # For each stop, find the Oklch lightness that produces a
  # colour with the target contrast against bg. Probes both
  # directions (lighter and darker than bg) and picks the better
  # fit, mirroring the logic in Color.Palette.Contrast.
  defp find_stop(target, hue, chroma, bg, metric, gamut) do
    dark = search(0.0, 0.5, target, hue, chroma, bg, metric, gamut)
    light = search(0.5, 1.0, target, hue, chroma, bg, metric, gamut)

    case best(target, dark, light) do
      {achieved, color} -> {achieved, color}
      :unreachable -> {target, oklch_to_srgb_clamped(hue, chroma, bg, gamut)}
    end
  end

  defp search(lo, hi, target, hue, chroma, bg, metric, gamut) do
    {c_lo, _} = probe(lo, hue, chroma, bg, metric, gamut)
    {c_hi, _} = probe(hi, hue, chroma, bg, metric, gamut)
    reachable = max(c_lo, c_hi)

    if reachable < target do
      :unreachable
    else
      direction = if c_hi > c_lo, do: :hi, else: :lo
      bisect(lo, hi, target, hue, chroma, bg, metric, gamut, direction, @binary_search_iterations)
    end
  end

  defp bisect(lo, hi, target, hue, chroma, bg, metric, gamut, direction, iterations) do
    mid = (lo + hi) / 2
    {achieved, color} = probe(mid, hue, chroma, bg, metric, gamut)

    cond do
      iterations == 0 ->
        {achieved, color}

      achieved == target ->
        {achieved, color}

      achieved < target ->
        case direction do
          :hi ->
            bisect(mid, hi, target, hue, chroma, bg, metric, gamut, direction, iterations - 1)

          :lo ->
            bisect(lo, mid, target, hue, chroma, bg, metric, gamut, direction, iterations - 1)
        end

      achieved > target ->
        case direction do
          :hi ->
            bisect(lo, mid, target, hue, chroma, bg, metric, gamut, direction, iterations - 1)

          :lo ->
            bisect(mid, hi, target, hue, chroma, bg, metric, gamut, direction, iterations - 1)
        end
    end
  end

  defp probe(l, hue, chroma, bg, metric, gamut) do
    {:ok, mapped} = Color.Gamut.to_gamut(%Color.Oklch{l: l, c: chroma, h: hue}, gamut)
    {measure(mapped, bg, metric), mapped}
  end

  defp best(_target, :unreachable, :unreachable), do: :unreachable
  defp best(_target, :unreachable, v), do: v
  defp best(_target, v, :unreachable), do: v

  defp best(target, {a_c, a}, {b_c, b}) do
    if abs(a_c - target) <= abs(b_c - target), do: {a_c, a}, else: {b_c, b}
  end

  defp measure(color, bg, :wcag), do: Color.Contrast.wcag_ratio(color, bg)
  defp measure(color, bg, :apca), do: abs(Color.Contrast.apca(color, bg))

  defp oklch_to_srgb_clamped(hue, chroma, _bg, gamut) do
    {:ok, mapped} = Color.Gamut.to_gamut(%Color.Oklch{l: 0.5, c: chroma, h: hue}, gamut)
    mapped
  end

  defp nearest_by_contrast(computed, target_contrast) do
    {label, _a, _c} =
      Enum.min_by(computed, fn {_label, achieved, _color} ->
        abs(achieved - target_contrast)
      end)

    label
  end

  # ---- validation ---------------------------------------------------------

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
      |> Keyword.put_new(:guarantee, @default_guarantee)
      |> Keyword.put_new(:background, @default_background)
      |> Keyword.put_new(:metric, @default_metric)
      |> Keyword.put_new(:hue_drift, @default_hue_drift)
      |> Keyword.put_new(:gamut, @default_gamut)

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

      not Enum.all?(stops, &is_number/1) ->
        raise Color.PaletteError,
          reason: :invalid_stops,
          detail: ":stops must be a list of numbers for ContrastScale"

      length(Enum.uniq(stops)) != length(stops) ->
        raise Color.PaletteError,
          reason: :duplicate_stops,
          detail: ":stops must not contain duplicates"

      true ->
        :ok
    end

    case Keyword.fetch!(options, :guarantee) do
      {ratio, apart} when is_number(ratio) and is_number(apart) and ratio > 1 and apart > 0 ->
        :ok

      other ->
        raise Color.PaletteError,
          reason: :invalid_guarantee,
          detail:
            ":guarantee must be {ratio, apart} with ratio > 1 and apart > 0, got #{inspect(other)}"
    end

    metric = Keyword.fetch!(options, :metric)

    unless metric in @valid_metrics do
      raise Color.PaletteError,
        reason: :invalid_metric,
        detail: "#{inspect(metric)} (valid: #{inspect(@valid_metrics)})"
    end

    options
  end
end
