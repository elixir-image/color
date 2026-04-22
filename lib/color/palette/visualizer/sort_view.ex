defmodule Color.Palette.Visualizer.SortView do
  @moduledoc false

  alias Color.Palette.Sort
  alias Color.Palette.Visualizer.Render

  # Default seed set — hand-picked to show off the strategies:
  # primaries, secondaries, a few named colours, two grays, a
  # brown, a pink, and a dark violet. Mixed hex and CSS named
  # forms demonstrate that `Color.new/1` accepts either.
  @default_colors_text """
  #ff0000
  orange
  #ffff00
  #00ff00
  cyan
  #0000ff
  magenta
  saddlebrown
  hotpink
  gold
  indigo
  #808080
  white
  black
  """

  @strategy_options [
    {:hue_lightness, "Hue → lightness (rainbow)"},
    {:stepped_hue, "Stepped hue (swatch grid)"},
    {:lightness, "Lightness only"}
  ]

  @grays_options [
    {:before, "Before chromatic colours"},
    {:after, "After chromatic colours"},
    {:exclude, "Exclude grays entirely"}
  ]

  def render(params, base) do
    colors_text = Map.get(params, :colors, default_colors_text())
    strategy = Map.get(params, :strategy, :hue_lightness)
    chroma_threshold = Map.get(params, :chroma_threshold, 0.02)
    hue_origin = Map.get(params, :hue_origin, 0.0)
    grays = Map.get(params, :grays, :before)
    buckets = Map.get(params, :buckets, 8)

    inputs = parse_colors(colors_text)

    {body, error} = build_body(inputs, strategy, chroma_threshold, hue_origin, grays, buckets)

    Render.page(
      title: "Sort",
      active: "sort",
      seed: Map.get(params, :seed, "#3b82f6"),
      body: body,
      error: error,
      base: base,
      hide_seed: true,
      extra_fields:
        extra_fields(strategy, chroma_threshold, hue_origin, grays, buckets, colors_text)
    )
  end

  @doc "Default textarea contents — used by the router when no `colors` param is supplied."
  def default_colors_text, do: @default_colors_text

  # ---- form fields -------------------------------------------------------

  defp extra_fields(strategy, chroma_threshold, hue_origin, grays, buckets, colors_text) do
    [
      "<label>strategy <select name=\"strategy\">",
      Enum.map(@strategy_options, fn {atom, label} ->
        selected = if atom == strategy, do: " selected", else: ""

        [
          "<option value=\"",
          Atom.to_string(atom),
          "\"",
          selected,
          ">",
          Render.escape(label),
          "</option>"
        ]
      end),
      "</select></label>",
      "<label>grays <select name=\"grays\">",
      Enum.map(@grays_options, fn {atom, label} ->
        selected = if atom == grays, do: " selected", else: ""

        [
          "<option value=\"",
          Atom.to_string(atom),
          "\"",
          selected,
          ">",
          Render.escape(label),
          "</option>"
        ]
      end),
      "</select></label>",
      "<label>hue origin <input type=\"number\" name=\"hue_origin\"",
      " min=\"0\" max=\"359.999\" step=\"1\" value=\"",
      format_number(hue_origin),
      "\"></label>",
      "<label>chroma threshold <input type=\"number\" name=\"chroma_threshold\"",
      " min=\"0\" max=\"0.5\" step=\"0.005\" value=\"",
      format_number(chroma_threshold),
      "\"></label>",
      "<label>buckets <input type=\"number\" name=\"buckets\"",
      " min=\"2\" max=\"32\" step=\"1\" value=\"",
      Integer.to_string(buckets),
      "\"></label>",
      # Full-width break so the textarea drops to its own row
      # below all the single-line controls.
      "<div style=\"order:999;flex-basis:100%;display:flex;flex-direction:column;gap:4px\">",
      "<label style=\"display:block\">colors (one per line — any form accepted by <code>Color.new/1</code>)</label>",
      "<textarea name=\"colors\" rows=\"8\" ",
      "style=\"width:100%;font-family:ui-monospace,monospace;font-size:12px;",
      "background:var(--vz-bg);color:var(--vz-text);border:1px solid var(--vz-border);",
      "border-radius:6px;padding:8px;min-width:0\">",
      Render.escape(colors_text),
      "</textarea>",
      "</div>"
    ]
  end

  # ---- body --------------------------------------------------------------

  defp build_body(inputs, strategy, chroma_threshold, hue_origin, grays, buckets) do
    try do
      sorted =
        Sort.sort(inputs,
          strategy: strategy,
          chroma_threshold: chroma_threshold,
          hue_origin: hue_origin,
          grays: grays,
          buckets: buckets
        )

      {success_body(inputs, sorted, strategy), nil}
    rescue
      e in Color.PaletteError ->
        {[], Exception.message(e)}

      e ->
        {[], Exception.message(e)}
    end
  end

  defp success_body(inputs, sorted, strategy) do
    [
      "<section class=\"vz-section\">",
      "<h2>Sorted (",
      Render.escape(strategy_label(strategy)),
      ")</h2>",
      sort_strip(sorted),
      "</section>",
      "<section class=\"vz-section\">",
      "<h2>Input order</h2>",
      sort_strip(inputs),
      "</section>"
    ]
  end

  defp sort_strip(colors) do
    [
      "<div class=\"vz-strip\">",
      Enum.map(colors, &swatch/1),
      "</div>"
    ]
  end

  defp swatch(color) do
    hex = Color.to_hex(color)
    {:ok, oklch} = Color.convert(color, Color.Oklch)
    text = Render.text_on(color)

    [
      "<div class=\"vz-swatch\">",
      "<div class=\"vz-chip\" style=\"background:",
      hex,
      ";color:",
      text,
      "\">",
      Render.escape(hex),
      "</div>",
      "<div class=\"vz-meta\">",
      "<div class=\"vz-hex\">",
      Render.escape(hex),
      "</div>",
      "<div>L\u00A0",
      Render.fmt(oklch.l || 0.0, 3),
      " C\u00A0",
      Render.fmt(oklch.c || 0.0, 3),
      " H\u00A0",
      Render.fmt(oklch.h || 0.0, 1),
      "</div>",
      "</div>",
      "</div>"
    ]
  end

  defp strategy_label(strategy) do
    @strategy_options
    |> Enum.find_value(to_string(strategy), fn {atom, label} ->
      if atom == strategy, do: label
    end)
  end

  # ---- input parsing -----------------------------------------------------

  @doc false
  @spec parse_colors(binary()) :: [Color.SRGB.t()]
  def parse_colors(text) when is_binary(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or (String.starts_with?(&1, "#") and comment_line?(&1))))
    |> Enum.map(&parse_one/1)
    |> Enum.reject(&is_nil/1)
  end

  # A hex colour (#rgb / #rrggbb / #rrggbbaa) is always treated
  # as a colour. Only lines that start with `#` *followed by
  # whitespace* (or end-of-line) are considered comments.
  defp comment_line?(line) do
    String.starts_with?(line, "# ") or line == "#"
  end

  defp parse_one(str) do
    case Color.new(str) do
      {:ok, srgb} -> srgb
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp format_number(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, decimals: 3])

  defp format_number(value) when is_integer(value), do: Integer.to_string(value)
  defp format_number(value), do: to_string(value)
end
