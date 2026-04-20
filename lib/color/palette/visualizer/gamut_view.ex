defmodule Color.Palette.Visualizer.GamutView do
  @moduledoc false

  alias Color.Palette.Visualizer.Render

  # Working spaces shown as togglable triangles. Each entry:
  # {atom, display label, hex outline, default-on?}.
  @working_spaces [
    {:SRGB, "sRGB", "#60a5fa", true},
    {:P3_D65, "Display P3", "#22c55e", true},
    {:Rec2020, "Rec. 2020", "#f59e0b", false},
    {:Adobe, "Adobe RGB", "#a855f7", false},
    {:ProPhoto, "ProPhoto RGB", "#f43f5e", false}
  ]

  # Palette-gamut dropdown options — mirrors TonalView so the
  # gamut view can reproduce the same tonal palette the Tonal tab
  # would generate.
  @palette_gamut_options [
    {:SRGB, "sRGB"},
    {:P3_D65, "P3 (D65)"},
    {:Rec2020, "Rec2020"},
    {:Adobe, "Adobe RGB"},
    {:ProPhoto, "ProPhoto"}
  ]

  def render(params, base) do
    projection = Map.get(params, :projection, :uv)
    enabled = Map.get(params, :gamuts, default_gamuts())
    show_planck = Map.get(params, :planckian, true)
    overlay_seed = Map.get(params, :overlay_seed, true)
    overlay_palette = Map.get(params, :overlay_palette, false)
    palette_gamut = Map.get(params, :palette_gamut, :SRGB)
    palette_chroma_ceiling = Map.get(params, :palette_chroma_ceiling, 1.0)
    seed = Map.get(params, :seed, "#3b82f6")

    body =
      try do
        success_body(
          projection,
          enabled,
          show_planck,
          overlay_seed,
          overlay_palette,
          seed,
          palette_gamut,
          palette_chroma_ceiling
        )
      rescue
        e ->
          ["<div class=\"vz-error\">", Render.escape(Exception.message(e)), "</div>"]
      end

    Render.page(
      title: "Gamut",
      active: "gamut",
      seed: seed,
      body: body,
      base: base,
      extra_fields:
        extra_fields(
          projection,
          enabled,
          show_planck,
          overlay_seed,
          overlay_palette,
          palette_gamut,
          palette_chroma_ceiling
        ),
      tab_params: %{
        "tonal" => %{
          "gamut" => Atom.to_string(palette_gamut),
          "chroma_ceiling" => format_ceiling(palette_chroma_ceiling)
        }
      }
    )
  end

  defp default_gamuts do
    for {atom, _label, _colour, default?} <- @working_spaces, default?, do: atom
  end

  defp extra_fields(
         projection,
         enabled,
         show_planck,
         overlay_seed,
         overlay_palette,
         palette_gamut,
         palette_chroma_ceiling
       ) do
    [
      "<label>proj <select name=\"projection\">",
      option("uv", "u′v′ (CIE 1976)", projection == :uv),
      option("xy", "xy (CIE 1931)", projection == :xy),
      "</select></label>",
      Enum.map(@working_spaces, fn {atom, label, _colour, _} ->
        key = Atom.to_string(atom)
        checked = if atom in enabled, do: " checked", else: ""

        [
          "<label style=\"display:inline-flex;align-items:center;gap:4px\">",
          "<input type=\"checkbox\" name=\"gamut[]\" value=\"",
          key,
          "\"",
          checked,
          "> ",
          Render.escape(label),
          "</label>"
        ]
      end),
      "<label><input type=\"checkbox\" name=\"planckian\" value=\"1\"",
      if(show_planck, do: " checked", else: ""),
      "> Planckian locus</label>",
      "<label><input type=\"checkbox\" name=\"overlay_seed\" value=\"1\"",
      if(overlay_seed, do: " checked", else: ""),
      "> Plot seed</label>",
      "<label><input type=\"checkbox\" name=\"overlay_palette\" value=\"1\"",
      if(overlay_palette, do: " checked", else: ""),
      "> Plot tonal palette</label>",
      "<label>palette gamut <select name=\"palette_gamut\">",
      Enum.map(@palette_gamut_options, fn {atom, label} ->
        selected = if atom == palette_gamut, do: " selected", else: ""
        ["<option value=\"", Atom.to_string(atom), "\"", selected, ">", label, "</option>"]
      end),
      "</select></label>",
      "<label>palette ceiling <input type=\"number\" name=\"palette_chroma_ceiling\"",
      " min=\"0.1\" max=\"1.0\" step=\"0.05\" value=\"",
      format_ceiling(palette_chroma_ceiling),
      "\"></label>",
      "<input type=\"hidden\" name=\"submitted\" value=\"1\">"
    ]
  end

  defp format_ceiling(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp format_ceiling(value) when is_integer(value), do: Integer.to_string(value)
  defp format_ceiling(value), do: to_string(value)

  defp option(value, label, selected?) do
    [
      "<option value=\"",
      value,
      "\"",
      if(selected?, do: " selected", else: ""),
      ">",
      Render.escape(label),
      "</option>"
    ]
  end

  defp success_body(
         projection,
         enabled,
         show_planck,
         overlay_seed,
         overlay_palette,
         seed,
         palette_gamut,
         palette_chroma_ceiling
       ) do
    palette =
      if overlay_palette,
        do: safe_tonal(seed, palette_gamut, palette_chroma_ceiling),
        else: nil

    svg_binary =
      Color.Gamut.SVG.render(
        projection: projection,
        gamuts: enabled,
        planckian: show_planck,
        seed: if(overlay_seed, do: seed),
        palette: palette
      )

    # Stamp the visualizer's CSS class on the <svg> so page CSS
    # resizes it to the container. The public renderer doesn't
    # know about our stylesheet.
    svg_for_page = String.replace(svg_binary, "<svg ", "<svg class=\"vz-gamut\" ", global: false)

    [
      "<section class=\"vz-section\">",
      "<h2>Chromaticity diagram (",
      projection_label(projection),
      ")</h2>",
      "<div class=\"vz-gamut-wrapper\">",
      svg_for_page,
      legend(enabled, show_planck, overlay_seed, overlay_palette, seed),
      "</div>",
      "</section>",
      svg_export(svg_binary)
    ]
  end

  defp safe_tonal(seed, gamut, chroma_ceiling) do
    Color.Palette.Tonal.new(seed, gamut: gamut, chroma_ceiling: chroma_ceiling)
  rescue
    _ -> nil
  end

  defp svg_export(svg_binary) do
    [
      "<section class=\"vz-section\">",
      "<h2>SVG export</h2>",
      "<div class=\"vz-export\">",
      Render.escape(svg_binary),
      "</div>",
      "</section>"
    ]
  end

  defp projection_label(:xy), do: "CIE 1931 x, y"
  defp projection_label(:uv), do: "CIE 1976 u′, v′"

  # ---- Legend ------------------------------------------------------------

  defp legend(enabled, show_planck, overlay_seed, overlay_palette, seed) do
    triangles_for_legend =
      for {atom, label, colour, _} <- @working_spaces, atom in enabled do
        {atom, label, colour, Color.Gamut.Diagram.triangle(atom, :xy)}
      end

    [
      "<div class=\"vz-gamut-legend\">",
      "<h3>Legend</h3>",
      "<ul>",
      "<li><span class=\"vz-legend-swatch\" style=\"background:rgba(255,255,255,0.25);border:1px solid #94a3b8\"></span>Visible spectrum (spectral locus)</li>",
      Enum.map(triangles_for_legend, fn {_atom, label, colour, tri} ->
        [
          "<li><span class=\"vz-legend-swatch\" style=\"background:",
          colour,
          "33;border:1.5px solid ",
          colour,
          "\"></span>",
          Render.escape(label),
          " <span style=\"color:var(--vz-text-faint);font-size:11px\">(WP ",
          Render.fmt(tri.white.x, 3),
          ", ",
          Render.fmt(tri.white.y, 3),
          ")</span></li>"
        ]
      end),
      "<li><span class=\"vz-legend-swatch\" ",
      "style=\"background:#60a5fa;border-radius:50%;border:1px solid rgba(255,255,255,0.4)\"></span>",
      "White point of each gamut (dot inside its triangle)</li>",
      if show_planck do
        [
          "<li><span class=\"vz-legend-swatch\" style=\"background:#fbbf2433;border:1px dashed #fbbf24\"></span>Planckian locus (1500 – 20 000 K)</li>"
        ]
      else
        []
      end,
      if overlay_seed do
        hex = Render.resolve_hex(seed, "#000000")

        [
          "<li><span class=\"vz-legend-swatch\" style=\"background:",
          hex,
          ";border:2px solid #fff\"></span>Seed: ",
          Render.escape(seed),
          "</li>"
        ]
      else
        []
      end,
      if overlay_palette do
        [
          "<li><span class=\"vz-legend-swatch\" ",
          "style=\"background:linear-gradient(90deg,#e0f2fe,#3b82f6,#0c1e4a);",
          "border:1px solid rgba(255,255,255,0.35)\"></span>",
          "Tonal palette (hover a dot for label / hex)</li>"
        ]
      else
        []
      end,
      "</ul>",
      "</div>"
    ]
  end
end
