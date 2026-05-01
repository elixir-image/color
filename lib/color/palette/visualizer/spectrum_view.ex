defmodule Color.Palette.Visualizer.SpectrumView do
  @moduledoc false

  alias Color.Palette.Visualizer.Render
  alias Color.Palette.Visualizer.SortView

  # The hue spectrum is a diagnostic view: take a list of colours
  # (a tonal scale, a theme, a hand-rolled bag of swatches) and
  # plot where they sit on the Oklch hue circle, with a separate
  # strip for achromatic entries laid out by lightness. The
  # binning approach is borrowed from image-pixel spectrum
  # generators (Hinton, "Generating a Color Spectrum for an
  # Image"): a wraparound hue axis cut at a configurable origin,
  # achromatic pixels separated by a chroma threshold, and a
  # column per bin whose height tracks input mass.

  @default_bin_width 4.0
  @default_chroma_threshold 0.02
  @default_hue_origin 15.0
  @default_achromatic_bins 24

  @svg_width 960
  @chromatic_height 280
  @achromatic_height 64
  @spectrum_padding 24

  def render(params, base) do
    colors_text = Map.get(params, :colors, default_colors_text())
    bin_width = Map.get(params, :bin_width, @default_bin_width)
    chroma_threshold = Map.get(params, :chroma_threshold, @default_chroma_threshold)
    hue_origin = Map.get(params, :hue_origin, @default_hue_origin)

    inputs = SortView.parse_colors(colors_text)
    {body, error} = build_body(inputs, bin_width, chroma_threshold, hue_origin)

    Render.page(
      title: "Spectrum",
      active: "spectrum",
      seed: Map.get(params, :seed, "#3b82f6"),
      body: body,
      error: error,
      base: base,
      hide_seed: true,
      extra_fields: extra_fields(bin_width, chroma_threshold, hue_origin, colors_text)
    )
  end

  @doc "Default textarea contents — used by the router when no `colors` param is supplied."
  def default_colors_text, do: SortView.default_colors_text()

  # ---- form fields -------------------------------------------------------

  defp extra_fields(bin_width, chroma_threshold, hue_origin, colors_text) do
    [
      "<label>bin width° <input type=\"number\" name=\"bin_width\"",
      " min=\"1\" max=\"30\" step=\"1\" value=\"",
      format_number(bin_width),
      "\"></label>",
      "<label>hue origin <input type=\"number\" name=\"hue_origin\"",
      " min=\"0\" max=\"359.999\" step=\"1\" value=\"",
      format_number(hue_origin),
      "\"></label>",
      "<label>chroma threshold <input type=\"number\" name=\"chroma_threshold\"",
      " min=\"0\" max=\"0.5\" step=\"0.005\" value=\"",
      format_number(chroma_threshold),
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

  defp build_body([], _bw, _ct, _ho) do
    {[
       "<section class=\"vz-section\">",
       "<h2>Spectrum</h2>",
       "<p>Add one or more colours in the textarea to see their hue distribution.</p>",
       "</section>"
     ], nil}
  end

  defp build_body(inputs, bin_width, chroma_threshold, hue_origin) do
    try do
      items = Enum.map(inputs, &prepare/1)
      {chromatic, achromatic} = partition(items, chroma_threshold)

      svg = render_svg(chromatic, achromatic, bin_width, hue_origin)
      summary = render_summary(items, chromatic, achromatic, chroma_threshold)

      body = [
        "<section class=\"vz-section\">",
        "<h2>Hue spectrum</h2>",
        svg,
        "</section>",
        "<section class=\"vz-section\">",
        "<h2>Summary</h2>",
        summary,
        "</section>"
      ]

      {body, nil}
    rescue
      e -> {[], Exception.message(e)}
    end
  end

  defp prepare(srgb) do
    {:ok, oklch} = Color.convert(srgb, Color.Oklch)
    %{
      output: srgb,
      hex: Color.to_hex(srgb),
      l: oklch.l || 0.0,
      c: oklch.c || 0.0,
      h: oklch.h || 0.0,
      mass: 1.0
    }
  end

  defp partition(items, chroma_threshold) do
    Enum.split_with(items, fn item -> item.c >= chroma_threshold end)
  end

  # ---- SVG ---------------------------------------------------------------

  defp render_svg(chromatic, achromatic, bin_width, hue_origin) do
    n_bins = max(1, round(360.0 / bin_width))
    bin_actual = 360.0 / n_bins

    chromatic_bins = bin_chromatic(chromatic, bin_actual, hue_origin)
    achromatic_bins = bin_achromatic(achromatic, @default_achromatic_bins)

    max_mass =
      [chromatic_bins, achromatic_bins]
      |> Enum.flat_map(fn bins -> Enum.map(bins, fn {_idx, items} -> total_mass(items) end) end)
      |> Enum.max(fn -> 1.0 end)
      |> max(1.0)

    plot_width = @svg_width - 2 * @spectrum_padding
    chromatic_x0 = @spectrum_padding
    chromatic_y0 = @spectrum_padding
    chromatic_y1 = chromatic_y0 + @chromatic_height
    achromatic_y0 = chromatic_y1 + 24
    achromatic_y1 = achromatic_y0 + @achromatic_height

    height = achromatic_y1 + @spectrum_padding

    [
      "<div class=\"vz-spectrum\" style=\"max-width:100%;overflow-x:auto\">",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ",
      Integer.to_string(@svg_width),
      " ",
      Integer.to_string(height),
      "\" role=\"img\" aria-label=\"Hue spectrum of palette\" ",
      "style=\"display:block;width:100%;height:auto\">",

      # baseline
      "<rect x=\"",
      Integer.to_string(chromatic_x0),
      "\" y=\"",
      Integer.to_string(chromatic_y1),
      "\" width=\"",
      Integer.to_string(plot_width),
      "\" height=\"1\" fill=\"var(--vz-border)\"/>",

      # chromatic bins
      Enum.map(chromatic_bins, fn {idx, items} ->
        bin_column(
          chromatic_x0 + idx * (plot_width / n_bins),
          plot_width / n_bins,
          chromatic_y1,
          @chromatic_height,
          items,
          max_mass
        )
      end),

      # achromatic strip label
      "<text x=\"",
      Integer.to_string(chromatic_x0),
      "\" y=\"",
      Integer.to_string(achromatic_y0 - 6),
      "\" font-family=\"ui-monospace,monospace\" font-size=\"11\" fill=\"var(--vz-muted, #888)\">achromatic (lightness)</text>",

      # achromatic bins
      Enum.map(achromatic_bins, fn {idx, items} ->
        bin_column(
          chromatic_x0 + idx * (plot_width / @default_achromatic_bins),
          plot_width / @default_achromatic_bins,
          achromatic_y1,
          @achromatic_height,
          items,
          max_mass
        )
      end),

      # hue axis ticks (every 60°, accounting for origin)
      hue_ticks(chromatic_x0, plot_width, n_bins, bin_actual, hue_origin, chromatic_y1),
      "</svg>",
      "</div>"
    ]
  end

  # Place each chromatic input into its hue bin; preserve all
  # contributors so the column can stack them by lightness.
  defp bin_chromatic(items, bin_actual, hue_origin) do
    items
    |> Enum.group_by(fn item ->
      offset = :math.fmod(item.h - hue_origin + 360.0, 360.0)
      min(trunc(offset / bin_actual), round(360.0 / bin_actual) - 1)
    end)
    |> Enum.into([])
  end

  # Achromatic items are laid out by lightness, in `n_bins`
  # buckets across [0.0, 1.0].
  defp bin_achromatic(items, n_bins) do
    items
    |> Enum.group_by(fn item ->
      bucket = trunc(item.l * n_bins)
      min(bucket, n_bins - 1) |> max(0)
    end)
    |> Enum.into([])
  end

  defp total_mass(items), do: Enum.reduce(items, 0.0, fn i, acc -> acc + i.mass end)

  # Render one bin as a stack of coloured rects (one per
  # contributing input), ordered ascending by lightness so the
  # darkest member sits at the bottom and the lightest at the top.
  defp bin_column(x, width, baseline_y, max_height, items, max_mass) do
    sorted = Enum.sort_by(items, & &1.l)
    column_total = total_mass(sorted)
    column_height = column_total / max_mass * max_height

    {_running, rects} =
      Enum.reduce(sorted, {0.0, []}, fn item, {acc_h, rects} ->
        rect_h = item.mass / max_mass * max_height

        rect = [
          "<rect x=\"",
          fmt_num(x + 0.5),
          "\" y=\"",
          fmt_num(baseline_y - acc_h - rect_h),
          "\" width=\"",
          fmt_num(max(width - 1, 0.5)),
          "\" height=\"",
          fmt_num(rect_h),
          "\" fill=\"",
          item.hex,
          "\"><title>",
          Render.escape(item.hex),
          "  L ",
          Render.fmt(item.l, 3),
          "  C ",
          Render.fmt(item.c, 3),
          "  H ",
          Render.fmt(item.h, 1),
          "</title></rect>"
        ]

        {acc_h + rect_h, [rect | rects]}
      end)

    # Rects accumulated bottom-up. Reverse so darkest is rendered
    # first (lowest in stack), lightest last.
    [
      "<g data-bin-mass=\"",
      Render.fmt(column_total, 2),
      "\" data-bin-height=\"",
      Render.fmt(column_height, 1),
      "\">",
      Enum.reverse(rects),
      "</g>"
    ]
  end

  defp hue_ticks(x0, plot_width, _n_bins, _bin_actual, hue_origin, baseline_y) do
    # Mark every 60° on the actual (un-offset) hue axis. The tick
    # x-position depends on the hue origin: a tick at hue H sits
    # at offset (H - hue_origin) mod 360.
    Enum.map(0..5, fn i ->
      hue_deg = i * 60
      offset = :math.fmod(hue_deg - hue_origin + 360.0, 360.0)
      x = x0 + offset / 360.0 * plot_width

      [
        "<line x1=\"",
        fmt_num(x),
        "\" y1=\"",
        Integer.to_string(baseline_y),
        "\" x2=\"",
        fmt_num(x),
        "\" y2=\"",
        Integer.to_string(baseline_y + 4),
        "\" stroke=\"var(--vz-border)\"/>",
        "<text x=\"",
        fmt_num(x + 2),
        "\" y=\"",
        Integer.to_string(baseline_y + 14),
        "\" font-family=\"ui-monospace,monospace\" font-size=\"10\" fill=\"var(--vz-muted, #888)\">",
        Integer.to_string(hue_deg),
        "°</text>"
      ]
    end)
  end

  # ---- summary -----------------------------------------------------------

  defp render_summary(items, chromatic, achromatic, chroma_threshold) do
    total = length(items)
    n_chrom = length(chromatic)
    n_achrom = length(achromatic)

    chrom_pct = if total == 0, do: 0.0, else: n_chrom / total * 100.0
    achrom_pct = if total == 0, do: 0.0, else: n_achrom / total * 100.0

    [
      "<dl class=\"vz-meta\" style=\"display:grid;grid-template-columns:max-content auto;gap:4px 16px\">",
      "<dt>Total inputs</dt><dd>",
      Integer.to_string(total),
      "</dd>",
      "<dt>Chromatic (C ≥ ",
      Render.fmt(chroma_threshold, 3),
      ")</dt><dd>",
      Integer.to_string(n_chrom),
      " (",
      Render.fmt(chrom_pct, 1),
      "%)</dd>",
      "<dt>Achromatic</dt><dd>",
      Integer.to_string(n_achrom),
      " (",
      Render.fmt(achrom_pct, 1),
      "%)</dd>",
      "</dl>"
    ]
  end

  # ---- formatting --------------------------------------------------------

  defp fmt_num(value) when is_number(value),
    do: :erlang.float_to_binary(value * 1.0, [:compact, decimals: 2])

  defp format_number(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, decimals: 3])

  defp format_number(value) when is_integer(value), do: Integer.to_string(value)
  defp format_number(value), do: to_string(value)
end
