defmodule Color.Palette.Visualizer.GamutView do
  @moduledoc false

  alias Color.Gamut.Diagram
  alias Color.Palette.Visualizer.Render

  # Working spaces shown as togglable triangles on the diagram.
  # Each entry is {atom, display label, hex outline colour,
  # default-on?}.
  @working_spaces [
    {:SRGB, "sRGB", "#60a5fa", true},
    {:P3_D65, "Display P3", "#22c55e", true},
    {:Rec2020, "Rec. 2020", "#f59e0b", false},
    {:Adobe, "Adobe RGB", "#a855f7", false},
    {:ProPhoto, "ProPhoto RGB", "#f43f5e", false}
  ]

  # SVG viewport: the diagram lives in a 800×700 box with a
  # generous margin so axis labels don't crop.
  @svg_width 800
  @svg_height 700
  @margin_left 70
  @margin_bottom 60
  @margin_top 20
  @margin_right 40

  # Chromaticity-space extents for each projection. Just enough
  # room around the locus to not crop the green corner.
  @xy_extent %{x: {0.0, 0.8}, y: {0.0, 0.9}}
  @uv_extent %{x: {0.0, 0.65}, y: {0.0, 0.6}}

  # Planckian locus annotation points (Kelvin), plotted as
  # labelled circles on the curve.
  @planck_annotations [2000, 2700, 4000, 6500, 10000]

  def render(params, base) do
    projection = Map.get(params, :projection, :uv)
    enabled = Map.get(params, :gamuts, default_gamuts())
    show_planck = Map.get(params, :planckian, true)
    overlay_seed = Map.get(params, :overlay_seed, true)
    overlay_palette = Map.get(params, :overlay_palette, false)
    seed = Map.get(params, :seed, "#3b82f6")

    body =
      try do
        success_body(projection, enabled, show_planck, overlay_seed, overlay_palette, seed)
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
      extra_fields: extra_fields(projection, enabled, show_planck, overlay_seed, overlay_palette)
    )
  end

  defp default_gamuts do
    for {atom, _label, _colour, default?} <- @working_spaces, default?, do: atom
  end

  defp extra_fields(projection, enabled, show_planck, overlay_seed, overlay_palette) do
    [
      "<label>proj <select name=\"projection\">",
      option("uv", "u′v′ (CIE 1976)", projection == :uv),
      option("xy", "xy (CIE 1931)", projection == :xy),
      "</select></label>",
      # Checkbox group for each working space.
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
      # Hidden marker so the server can tell "all boxes unchecked"
      # apart from "first render, no params at all". Without this
      # an empty submit would fall back to the defaults.
      "<input type=\"hidden\" name=\"submitted\" value=\"1\">"
    ]
  end

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

  defp success_body(projection, enabled, show_planck, overlay_seed, overlay_palette, seed) do
    locus = Diagram.spectral_locus(projection)

    planckian =
      if show_planck, do: Diagram.planckian_locus(1500..20000//500, projection), else: []

    seed_point =
      if overlay_seed do
        case Diagram.chromaticity(seed, projection) do
          {:ok, pt} -> pt
          _ -> nil
        end
      else
        nil
      end

    palette_track =
      if overlay_palette, do: build_palette_track(seed, projection), else: []

    triangles =
      for {atom, label, colour, _} <- @working_spaces, atom in enabled do
        {atom, label, colour, Diagram.triangle(atom, projection)}
      end

    svg_iodata = svg(projection, locus, triangles, planckian, palette_track, seed_point, seed)

    [
      "<section class=\"vz-section\">",
      "<h2>Chromaticity diagram (",
      projection_label(projection),
      ")</h2>",
      "<div class=\"vz-gamut-wrapper\">",
      svg_iodata,
      legend(triangles, show_planck, overlay_seed, overlay_palette, seed),
      "</div>",
      "</section>",
      svg_export(svg_iodata)
    ]
  end

  # Exports the rendered SVG as a copy-pasteable block, mirroring
  # the CSS / Tailwind / DTCG export blocks on the other views.
  defp svg_export(svg_iodata) do
    svg_text = svg_iodata |> IO.iodata_to_binary()

    [
      "<section class=\"vz-section\">",
      "<h2>SVG export</h2>",
      "<div class=\"vz-export\">",
      Render.escape(svg_text),
      "</div>",
      "</section>"
    ]
  end

  # For a given seed, generate a Tonal palette and return each stop's
  # chromaticity + the stop's hex colour, in label order. Returns [] if
  # the palette can't be built (unparseable seed, etc.).
  defp build_palette_track(seed, projection) do
    palette = Color.Palette.Tonal.new(seed)

    palette
    |> Color.Palette.Tonal.labels()
    |> Enum.map(fn label ->
      color = Map.fetch!(palette.stops, label)

      case Diagram.chromaticity(color, projection) do
        {:ok, point} ->
          %{
            label: label,
            hex: Color.to_hex(color),
            point: point,
            is_seed: label == palette.seed_stop
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  rescue
    _ -> []
  end

  defp projection_label(:xy), do: "CIE 1931 x, y"
  defp projection_label(:uv), do: "CIE 1976 u′, v′"

  # ---- SVG construction --------------------------------------------------

  defp svg(projection, locus, triangles, planckian, palette_track, seed_point, seed) do
    extent = extent_for(projection)
    transform = &to_pixel(&1, projection, extent)

    [
      "<svg viewBox=\"0 0 ",
      Integer.to_string(@svg_width),
      " ",
      Integer.to_string(@svg_height),
      "\" class=\"vz-gamut\" xmlns=\"http://www.w3.org/2000/svg\">",
      grid(extent, transform, projection),
      locus_path(locus, transform),
      axes(extent, projection, transform),
      Enum.map(triangles, fn {_atom, _label, colour, tri} ->
        triangle_svg(tri, colour, transform)
      end),
      planckian_svg(planckian, transform),
      palette_svg(palette_track, transform),
      seed_svg(seed_point, seed, transform),
      "</svg>"
    ]
  end

  # Transform a chromaticity point (with :x/:y or :u/:v keys) to
  # SVG pixel coordinates, inverting Y so the plot reads like a
  # textbook (yellow up).
  defp to_pixel(point, projection, extent) do
    {a, b} = coords(point, projection)
    {min_x, max_x} = extent.x
    {min_y, max_y} = extent.y

    plot_w = @svg_width - @margin_left - @margin_right
    plot_h = @svg_height - @margin_top - @margin_bottom

    px = @margin_left + (a - min_x) / (max_x - min_x) * plot_w
    py = @margin_top + plot_h - (b - min_y) / (max_y - min_y) * plot_h

    {px, py}
  end

  defp coords(%{x: x, y: y}, :xy), do: {x, y}
  defp coords(%{u: u, v: v}, :uv), do: {u, v}

  defp extent_for(:xy), do: @xy_extent
  defp extent_for(:uv), do: @uv_extent

  defp locus_path([], _transform), do: []

  defp locus_path(points, transform) do
    # Closed polyline: trace the visible-spectrum curve, then
    # close back to the first point across the "line of purples".
    d =
      points
      |> Enum.map(transform)
      |> Enum.map(fn {px, py} -> fmt(px) <> "," <> fmt(py) end)
      |> Enum.join(" ")

    [
      "<polygon points=\"",
      d,
      "\" fill=\"rgba(255,255,255,0.03)\" stroke=\"#94a3b8\" stroke-width=\"1\" />"
    ]
  end

  defp triangle_svg(tri, colour, transform) do
    [tri.red, tri.green, tri.blue]
    |> Enum.map(transform)
    |> then(fn [r, g, b] ->
      pts =
        [r, g, b]
        |> Enum.map(fn {x, y} -> fmt(x) <> "," <> fmt(y) end)
        |> Enum.join(" ")

      {wx, wy} = transform.(tri.white)

      [
        "<polygon points=\"",
        pts,
        "\" fill=\"",
        colour,
        "\" fill-opacity=\"0.08\" stroke=\"",
        colour,
        "\" stroke-width=\"1.5\" />",
        "<circle cx=\"",
        fmt(wx),
        "\" cy=\"",
        fmt(wy),
        "\" r=\"4\" fill=\"",
        colour,
        "\" />"
      ]
    end)
  end

  defp planckian_svg([], _transform), do: []

  defp planckian_svg(points, transform) do
    d =
      points
      |> Enum.map(&{&1.kelvin, transform.(&1)})
      |> Enum.map(fn {_k, {px, py}} -> fmt(px) <> "," <> fmt(py) end)
      |> Enum.join(" ")

    annotations =
      points
      |> Enum.filter(&(&1.kelvin in @planck_annotations))
      |> Enum.map(fn point ->
        {px, py} = transform.(point)

        [
          "<circle cx=\"",
          fmt(px),
          "\" cy=\"",
          fmt(py),
          "\" r=\"3\" fill=\"#fbbf24\" />",
          "<text x=\"",
          fmt(px + 6),
          "\" y=\"",
          fmt(py - 4),
          "\" fill=\"#fbbf24\" font-size=\"10\" font-family=\"ui-monospace,monospace\">",
          Integer.to_string(point.kelvin),
          "K</text>"
        ]
      end)

    [
      "<polyline points=\"",
      d,
      "\" fill=\"none\" stroke=\"#fbbf24\" stroke-width=\"1.2\" stroke-dasharray=\"3,3\" />",
      annotations
    ]
  end

  # Palette track: a thin polyline connecting every stop's
  # chromaticity, plus a filled circle per stop coloured with the
  # stop's own hex. A <title> per circle gives a browser tooltip
  # with the stop label and hex so hovering the SVG is useful.
  defp palette_svg([], _transform), do: []

  defp palette_svg(track, transform) do
    # Polyline through all stops first, under the circles.
    polyline_points =
      track
      |> Enum.map(&transform.(&1.point))
      |> Enum.map(fn {px, py} -> fmt(px) <> "," <> fmt(py) end)
      |> Enum.join(" ")

    circles =
      Enum.map(track, fn %{label: label, hex: hex, point: point, is_seed: is_seed?} ->
        {px, py} = transform.(point)

        # Slightly larger radius for the seed stop so it's easy to
        # pick out within the track; a thin white outline so every
        # circle reads against any triangle's fill.
        r = if is_seed?, do: "5", else: "3.5"
        stroke_width = if is_seed?, do: "1.5", else: "1"

        [
          "<circle cx=\"",
          fmt(px),
          "\" cy=\"",
          fmt(py),
          "\" r=\"",
          r,
          "\" fill=\"",
          hex,
          "\" stroke=\"#fff\" stroke-opacity=\"0.7\" stroke-width=\"",
          stroke_width,
          "\"><title>",
          to_string(label),
          ": ",
          hex,
          "</title></circle>"
        ]
      end)

    [
      "<polyline points=\"",
      polyline_points,
      "\" fill=\"none\" stroke=\"#ffffff\" stroke-opacity=\"0.35\" stroke-width=\"1\" />",
      circles
    ]
  end

  defp seed_svg(nil, _seed, _transform), do: []

  defp seed_svg(point, seed_input, transform) do
    {px, py} = transform.(point)
    hex = Render.resolve_hex(seed_input, "#000000")

    [
      "<circle cx=\"",
      fmt(px),
      "\" cy=\"",
      fmt(py),
      "\" r=\"7\" fill=\"",
      hex,
      "\" stroke=\"#fff\" stroke-width=\"2\" />",
      "<text x=\"",
      fmt(px + 10),
      "\" y=\"",
      fmt(py + 4),
      "\" fill=\"#fff\" font-size=\"11\" font-family=\"ui-monospace,monospace\">seed</text>"
    ]
  end

  # Minimal axes: bounding box + tick-labelled horizontal and
  # vertical baselines along the bottom and left.
  defp axes(extent, projection, transform) do
    {min_x, max_x} = extent.x
    {min_y, max_y} = extent.y

    ticks_x = axis_ticks(min_x, max_x)
    ticks_y = axis_ticks(min_y, max_y)

    x_label = if projection == :xy, do: "x", else: "u′"
    y_label = if projection == :xy, do: "y", else: "v′"

    [
      # X axis ticks + labels.
      Enum.map(ticks_x, fn value ->
        {px, py} =
          transform.(
            case projection do
              :xy -> %{x: value, y: min_y}
              :uv -> %{u: value, v: min_y}
            end
          )

        [
          "<line x1=\"",
          fmt(px),
          "\" y1=\"",
          fmt(py),
          "\" x2=\"",
          fmt(px),
          "\" y2=\"",
          fmt(py + 5),
          "\" stroke=\"#475569\" />",
          "<text x=\"",
          fmt(px),
          "\" y=\"",
          fmt(py + 18),
          "\" fill=\"#94a3b8\" font-size=\"11\" font-family=\"ui-monospace,monospace\" text-anchor=\"middle\">",
          format_tick(value),
          "</text>"
        ]
      end),
      # Y axis ticks + labels.
      Enum.map(ticks_y, fn value ->
        {px, py} =
          transform.(
            case projection do
              :xy -> %{x: min_x, y: value}
              :uv -> %{u: min_x, v: value}
            end
          )

        [
          "<line x1=\"",
          fmt(px - 5),
          "\" y1=\"",
          fmt(py),
          "\" x2=\"",
          fmt(px),
          "\" y2=\"",
          fmt(py),
          "\" stroke=\"#475569\" />",
          "<text x=\"",
          fmt(px - 8),
          "\" y=\"",
          fmt(py + 4),
          "\" fill=\"#94a3b8\" font-size=\"11\" font-family=\"ui-monospace,monospace\" text-anchor=\"end\">",
          format_tick(value),
          "</text>"
        ]
      end),
      # Axis titles.
      "<text x=\"",
      fmt(@svg_width / 2),
      "\" y=\"",
      Integer.to_string(@svg_height - 15),
      "\" fill=\"#e5e7eb\" font-size=\"13\" font-family=\"ui-monospace,monospace\" text-anchor=\"middle\">",
      x_label,
      "</text>",
      "<text x=\"20\" y=\"",
      fmt(@svg_height / 2),
      "\" fill=\"#e5e7eb\" font-size=\"13\" font-family=\"ui-monospace,monospace\" text-anchor=\"middle\" transform=\"rotate(-90 20 ",
      fmt(@svg_height / 2),
      ")\">",
      y_label,
      "</text>"
    ]
  end

  defp grid(extent, transform, projection) do
    {min_x, max_x} = extent.x
    {min_y, max_y} = extent.y

    vertical =
      Enum.map(axis_ticks(min_x, max_x), fn v ->
        {x1, _} = transform.(point_for(projection, v, min_y))
        {_, y2} = transform.(point_for(projection, v, max_y))
        {_, y1} = transform.(point_for(projection, v, min_y))

        [
          "<line x1=\"",
          fmt(x1),
          "\" y1=\"",
          fmt(y1),
          "\" x2=\"",
          fmt(x1),
          "\" y2=\"",
          fmt(y2),
          "\" stroke=\"#1f2937\" stroke-width=\"0.5\" />"
        ]
      end)

    horizontal =
      Enum.map(axis_ticks(min_y, max_y), fn v ->
        {_, y1} = transform.(point_for(projection, min_x, v))
        {x2, _} = transform.(point_for(projection, max_x, v))
        {x1, _} = transform.(point_for(projection, min_x, v))

        [
          "<line x1=\"",
          fmt(x1),
          "\" y1=\"",
          fmt(y1),
          "\" x2=\"",
          fmt(x2),
          "\" y2=\"",
          fmt(y1),
          "\" stroke=\"#1f2937\" stroke-width=\"0.5\" />"
        ]
      end)

    [vertical, horizontal]
  end

  defp point_for(:xy, x, y), do: %{x: x, y: y}
  defp point_for(:uv, u, v), do: %{u: u, v: v}

  # Tick values at 0.1 intervals from min to max.
  defp axis_ticks(min, max) do
    first = :math.ceil(min * 10) / 10
    Stream.iterate(first, &(&1 + 0.1)) |> Enum.take_while(&(&1 <= max + 1.0e-9))
  end

  defp format_tick(v) do
    :erlang.float_to_binary(v * 1.0, decimals: 1)
  end

  defp fmt(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 2)
  defp fmt(n), do: to_string(n)

  # ---- Legend ------------------------------------------------------------

  defp legend(triangles, show_planck, overlay_seed, overlay_palette, seed) do
    [
      "<div class=\"vz-gamut-legend\">",
      "<h3>Legend</h3>",
      "<ul>",
      "<li><span class=\"vz-legend-swatch\" style=\"background:rgba(255,255,255,0.25);border:1px solid #94a3b8\"></span>Visible spectrum (spectral locus)</li>",
      Enum.map(triangles, fn {_atom, label, colour, tri} ->
        {xw, yw} =
          case Map.get(tri.white, :x) do
            nil -> {tri.white.u, tri.white.v}
            x -> {x, tri.white.y}
          end

        [
          "<li><span class=\"vz-legend-swatch\" style=\"background:",
          colour,
          "33;border:1.5px solid ",
          colour,
          "\"></span>",
          Render.escape(label),
          " <span style=\"color:var(--vz-text-faint);font-size:11px\">(WP ",
          Render.fmt(xw, 3),
          ", ",
          Render.fmt(yw, 3),
          ")</span></li>"
        ]
      end),
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
