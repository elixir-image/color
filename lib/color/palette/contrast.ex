defmodule Color.Palette.Contrast do
  @moduledoc """
  A **contrast-targeted** palette — shades of a seed colour chosen
  so each stop hits a specific contrast ratio against a fixed
  background.

  This is the algorithm behind [Adobe Leonardo](https://leonardocolor.io/).
  Unlike `Color.Palette.Tonal`, which produces *visually* even
  lightness steps, this palette produces *contrast-wise* even
  steps. Each stop in the result satisfies the WCAG or APCA
  contrast ratio you asked for — exactly — against the background
  you specified.

  Use it when you need:

  * Component states (resting, hover, active, focus, disabled)
    that all meet a specific contrast requirement.

  * Text shades guaranteed to pass AA (4.5:1) or AAA (7:1) on a
    known surface.

  * APCA-driven text hierarchies, with `:metric: :apca` and
    targets in the 60–90 Lc range.

  ## Algorithm

  1. Convert the seed to **Oklch**. Keep its hue and chroma.

  2. For each target contrast ratio, **binary search** over Oklch
     lightness `L ∈ [0, 1]` for a colour whose contrast against
     the background matches the target. Contrast is monotonic in
     lightness (for a fixed hue / chroma), so binary search
     converges in ~20 iterations to sub-0.01 precision.

  3. Gamut-map each candidate into sRGB with `Color.Gamut`.

  4. If the search direction (lighter vs darker than background)
     can't reach the target, the stop is marked
     `:unreachable`. This happens when the target ratio is higher
     than what the seed's hue and chroma can achieve against the
     given background.

  ## Metrics

  * `:wcag` (default) — WCAG 2.x contrast ratio, via
    `Color.Contrast.wcag_ratio/2`. Targets typically in
    `[1.0, 21.0]`.

  * `:apca` — APCA W3 0.1.9 Lc value, via `Color.Contrast.apca/2`.
    Targets typically in `[15, 108]` (absolute value).

  """

  @default_wcag_targets [1.25, 1.5, 2.0, 3.0, 4.5, 7.0, 10.0, 15.0]
  @default_apca_targets [15, 30, 45, 60, 75, 90]

  @binary_search_iterations 24
  @valid_metrics [:wcag, :apca]
  @valid_keys [:background, :targets, :metric, :gamut, :name]

  defstruct [
    :name,
    :seed,
    :background,
    :metric,
    :stops,
    :options
  ]

  @type stop :: %{
          target: number(),
          achieved: number(),
          color: Color.SRGB.t() | :unreachable
        }

  @type t :: %__MODULE__{
          name: binary() | nil,
          seed: Color.SRGB.t(),
          background: Color.SRGB.t(),
          metric: :wcag | :apca,
          stops: [stop()],
          options: keyword()
        }

  @doc """
  Generates a contrast-targeted palette.

  ### Arguments

  * `seed` is anything accepted by `Color.new/1`. Its hue and
    chroma are preserved; lightness is swept to hit each target.

  ### Options

  * `:background` is the colour to measure contrast against.
    Defaults to `"white"`.

  * `:targets` is a list of target contrast values. Defaults to
    `[1.25, 1.5, 2.0, 3.0, 4.5, 7.0, 10.0, 15.0]` for WCAG or
    `[15, 30, 45, 60, 75, 90]` for APCA.

  * `:metric` is `:wcag` (default) or `:apca`.

  * `:gamut` is the working space to gamut-map each stop into,
    default `:SRGB`.

  * `:name` is an optional string label.

  ### Returns

  * A `Color.Palette.Contrast` struct. Each entry in `:stops` has
    `:target`, `:achieved`, and `:color` fields. `:color` is
    `:unreachable` if no lightness produces the requested contrast.

  ### Examples

      iex> palette = Color.Palette.Contrast.new("#3b82f6", targets: [3.0, 4.5, 7.0])
      iex> length(palette.stops)
      3
      iex> Enum.all?(palette.stops, & &1.color != :unreachable)
      true

  """
  @spec new(Color.input(), keyword()) :: t()
  def new(seed, options \\ []) do
    options = validate_options!(options)

    {:ok, seed_srgb} = Color.new(seed)
    {:ok, bg_srgb} = Color.new(Keyword.fetch!(options, :background))
    {:ok, seed_oklch} = Color.convert(seed_srgb, Color.Oklch)

    metric = Keyword.fetch!(options, :metric)
    gamut = Keyword.fetch!(options, :gamut)
    targets = Keyword.fetch!(options, :targets)

    base_h = seed_oklch.h || 0.0
    base_c = seed_oklch.c || 0.0

    stops =
      Enum.map(targets, fn target ->
        find_stop(target, base_h, base_c, bg_srgb, metric, gamut)
      end)

    %__MODULE__{
      name: Keyword.get(options, :name),
      seed: seed_srgb,
      background: bg_srgb,
      metric: metric,
      stops: stops,
      options: options
    }
  end

  @doc """
  Fetches the colour for a given target contrast from a palette.

  If the target was not in the original `:targets` list, or no
  lightness was found that satisfied it, returns `:error`.

  ### Arguments

  * `palette` is a `Color.Palette.Contrast` struct.

  * `target` is the contrast target to look up.

  ### Returns

  * `{:ok, color}` on success, `:error` otherwise.

  ### Examples

      iex> palette = Color.Palette.Contrast.new("#3b82f6", targets: [4.5, 7.0])
      iex> {:ok, _color} = Color.Palette.Contrast.fetch(palette, 4.5)
      iex> Color.Palette.Contrast.fetch(palette, 99.0)
      :error

  """
  @spec fetch(t(), number()) :: {:ok, Color.SRGB.t()} | :error
  def fetch(%__MODULE__{stops: stops}, target) do
    case Enum.find(stops, &(&1.target == target)) do
      %{color: %Color.SRGB{} = color} -> {:ok, color}
      _ -> :error
    end
  end

  @doc """
  Returns `true` when every reachable stop in the palette is
  inside the given RGB working space.

  Unreachable stops (`:unreachable` sentinel) are ignored — they
  have no colour to check.

  ### Arguments

  * `palette` is a `Color.Palette.Contrast` struct.

  * `working_space` is an RGB working-space atom. Defaults to
    `:SRGB`.

  ### Returns

  * A boolean.

  ### Examples

      iex> palette = Color.Palette.Contrast.new("#3b82f6", targets: [4.5, 7.0])
      iex> Color.Palette.Contrast.in_gamut?(palette, :SRGB)
      true

  """
  @spec in_gamut?(t(), Color.Types.working_space()) :: boolean()
  def in_gamut?(%__MODULE__{stops: stops}, working_space \\ :SRGB) do
    Enum.all?(stops, fn
      %{color: :unreachable} -> true
      %{color: color} -> Color.Gamut.in_gamut?(color, working_space)
    end)
  end

  @doc """
  Returns a detailed gamut report on a contrast palette.

  Each reachable stop becomes a `%{target, color, in_gamut?}`
  entry; unreachable stops become `%{target, color: :unreachable}`.

  ### Arguments

  * `palette` is a `Color.Palette.Contrast` struct.

  * `working_space` is an RGB working-space atom. Defaults to
    `:SRGB`.

  ### Returns

  * A map with `:working_space`, `:in_gamut?`, `:stops`, and
    `:out_of_gamut`.

  ### Examples

      iex> palette = Color.Palette.Contrast.new("#3b82f6", targets: [4.5, 7.0])
      iex> %{in_gamut?: true} = Color.Palette.Contrast.gamut_report(palette, :SRGB)

  """
  @spec gamut_report(t(), Color.Types.working_space()) :: map()
  def gamut_report(%__MODULE__{stops: stops}, working_space \\ :SRGB) do
    entries =
      Enum.map(stops, fn
        %{color: :unreachable} = stop ->
          %{target: stop.target, color: :unreachable, in_gamut?: true}

        %{color: color, target: target} ->
          %{
            target: target,
            color: color,
            in_gamut?: Color.Gamut.in_gamut?(color, working_space)
          }
      end)

    %{
      working_space: working_space,
      in_gamut?: Enum.all?(entries, & &1.in_gamut?),
      stops: entries,
      out_of_gamut: Enum.reject(entries, & &1.in_gamut?)
    }
  end

  @doc """
  Emits the palette as a W3C [Design Tokens Community Group](https://www.designtokens.org/)
  color-token group.

  Each reachable stop becomes a DTCG color token keyed by the
  target contrast value (integer if it rounds to one, otherwise
  decimal). Unreachable stops are emitted as tokens whose
  `$value` is `null` with an `$extensions.color.reason` field
  explaining the exclusion — tools that filter on `$value`
  presence will skip them cleanly.

  ### Arguments

  * `palette` is a `Color.Palette.Contrast` struct.

  ### Options

  * `:space` is the colour space for emitted stop values. Any
    module accepted by `Color.convert/2`. Default `Color.Oklch`.

  * `:name` overrides the group name. Defaults to the palette's
    `:name` field, or `"contrast"` if unset.

  ### Returns

  * A map shaped as `%{"<name>" => %{"<target>" => token, ...}}`.

  ### Examples

      iex> palette = Color.Palette.Contrast.new("#3b82f6", targets: [4.5, 7.0])
      iex> tokens = Color.Palette.Contrast.to_tokens(palette)
      iex> tokens["contrast"]["4.5"]["$type"]
      "color"

  """
  @spec to_tokens(t(), keyword()) :: map()
  def to_tokens(%__MODULE__{} = palette, options \\ []) do
    space = Keyword.get(options, :space, Color.Oklch)
    name = Keyword.get(options, :name, palette.name || "contrast")

    stop_tokens =
      Enum.into(palette.stops, %{}, fn stop ->
        key = format_target(stop.target)

        token =
          case stop do
            %{color: :unreachable} ->
              %{
                "$type" => "color",
                "$value" => nil,
                "$extensions" => %{
                  "color" => %{
                    "reason" => "unreachable",
                    "target" => stop.target,
                    "detail" =>
                      "No Oklch lightness produces contrast #{stop.target} against this background"
                  }
                }
              }

            %{color: color, achieved: achieved} ->
              base = Color.DesignTokens.encode_token(color, space: space)
              put_achieved(base, achieved, palette.metric)
          end

        {key, token}
      end)

    %{name => stop_tokens}
  end

  defp format_target(t) when is_integer(t), do: Integer.to_string(t)

  defp format_target(t) when is_float(t) do
    if t == Float.round(t),
      do: Integer.to_string(trunc(t)),
      else: :erlang.float_to_binary(t, [:short])
  end

  defp put_achieved(token, achieved, metric) do
    ext =
      token
      |> Map.get("$extensions", %{})
      |> Map.put("color", %{"achieved" => achieved, "metric" => Atom.to_string(metric)})

    Map.put(token, "$extensions", ext)
  end

  # ---- search -------------------------------------------------------------

  # Binary search over Oklch L for a colour at (h, c, L) whose
  # contrast against bg matches the target ratio. Tries both
  # "darker than background" and "lighter than background"
  # directions and picks the one that best hits the target.
  defp find_stop(target, h, c, bg, metric, gamut) do
    candidate_dark = search(0.0, 0.5, target, h, c, bg, metric, gamut)
    candidate_light = search(0.5, 1.0, target, h, c, bg, metric, gamut)

    case best_candidate(target, candidate_dark, candidate_light) do
      {achieved, color} when is_number(achieved) ->
        %{target: target, achieved: achieved, color: color}

      :unreachable ->
        %{target: target, achieved: nil, color: :unreachable}
    end
  end

  # 24 iterations of binary search in [lo, hi] Oklch L. We don't
  # know upfront which direction of L increases contrast, so we
  # probe both ends and set up the search to move toward the
  # endpoint with higher contrast.
  defp search(lo, hi, target, h, c, bg, metric, gamut) do
    contrast_at = fn l ->
      {:ok, mapped} = Color.Gamut.to_gamut(%Color.Oklch{l: l, c: c, h: h}, gamut)
      {contrast(mapped, bg, metric), mapped}
    end

    {c_lo, _} = contrast_at.(lo)
    {c_hi, _} = contrast_at.(hi)

    # The endpoint with higher contrast is where we want to move
    # toward. If neither endpoint reaches the target, we can't
    # satisfy it in this half.
    max_achievable = max(c_lo, c_hi)

    if max_achievable < target do
      :unreachable
    else
      increasing_toward = if c_hi > c_lo, do: :hi, else: :lo

      bisect(
        lo,
        hi,
        target,
        h,
        c,
        bg,
        metric,
        gamut,
        increasing_toward,
        @binary_search_iterations
      )
    end
  end

  defp bisect(lo, hi, target, h, c, bg, metric, gamut, direction, iterations) do
    mid = (lo + hi) / 2
    {:ok, mapped} = Color.Gamut.to_gamut(%Color.Oklch{l: mid, c: c, h: h}, gamut)
    achieved = contrast(mapped, bg, metric)

    cond do
      iterations == 0 ->
        {achieved, mapped}

      achieved == target ->
        {achieved, mapped}

      achieved < target ->
        # Need more contrast — move further in the "increasing"
        # direction.
        case direction do
          :hi -> bisect(mid, hi, target, h, c, bg, metric, gamut, direction, iterations - 1)
          :lo -> bisect(lo, mid, target, h, c, bg, metric, gamut, direction, iterations - 1)
        end

      achieved > target ->
        # Overshot — move back.
        case direction do
          :hi -> bisect(lo, mid, target, h, c, bg, metric, gamut, direction, iterations - 1)
          :lo -> bisect(mid, hi, target, h, c, bg, metric, gamut, direction, iterations - 1)
        end
    end
  end

  defp best_candidate(_target, :unreachable, :unreachable), do: :unreachable

  defp best_candidate(_target, :unreachable, {achieved, color}), do: {achieved, color}
  defp best_candidate(_target, {achieved, color}, :unreachable), do: {achieved, color}

  defp best_candidate(target, {achieved_a, color_a}, {achieved_b, color_b}) do
    if abs(achieved_a - target) <= abs(achieved_b - target) do
      {achieved_a, color_a}
    else
      {achieved_b, color_b}
    end
  end

  # ---- metrics ------------------------------------------------------------

  defp contrast(color, background, :wcag) do
    Color.Contrast.wcag_ratio(color, background)
  end

  defp contrast(color, background, :apca) do
    abs(Color.Contrast.apca(color, background))
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

    metric = Keyword.get(options, :metric, :wcag)

    unless metric in @valid_metrics do
      raise Color.PaletteError,
        reason: :invalid_metric,
        detail: "#{inspect(metric)} (valid metrics: #{inspect(@valid_metrics)})"
    end

    default_targets =
      case metric do
        :wcag -> @default_wcag_targets
        :apca -> @default_apca_targets
      end

    options =
      options
      |> Keyword.put_new(:background, "white")
      |> Keyword.put_new(:targets, default_targets)
      |> Keyword.put_new(:metric, metric)
      |> Keyword.put_new(:gamut, :SRGB)

    targets = Keyword.fetch!(options, :targets)

    cond do
      not is_list(targets) ->
        raise Color.PaletteError,
          reason: :invalid_targets,
          detail: ":targets must be a list"

      targets == [] ->
        raise Color.PaletteError,
          reason: :empty_targets,
          detail: ":targets must contain at least one value"

      Enum.any?(targets, &(not is_number(&1))) ->
        raise Color.PaletteError,
          reason: :invalid_targets,
          detail: ":targets must be a list of numbers"

      true ->
        :ok
    end

    options
  end
end
