defmodule Color.Gamut.SVG do
  @moduledoc """
  Renders a chromaticity diagram — the horseshoe, gamut
  triangles, Planckian locus, and optional palette / seed
  overlays — as a self-contained SVG string.

  The heavy lifting (spectral-locus points, working-space
  triangle vertices, Planckian coordinates) is done by
  `Color.Gamut.Diagram`; this module wraps that data in a
  complete, styleable SVG.

  Useful when you want to embed a chromaticity diagram in a
  design-system docs page, a README, an exported PDF, or any
  tool that speaks SVG. The same renderer is used by the
  `/gamut` tab of `Color.Palette.Visualizer`.

  ## Example

      iex> svg = Color.Gamut.SVG.render(projection: :uv, gamuts: [:SRGB, :P3_D65])
      iex> String.starts_with?(svg, "<svg viewBox=")
      true

  """

  alias Color.Gamut.Diagram

  # Default visual parameters.
  @default_width 800
  @default_height 700
  @default_margins %{left: 70, right: 40, top: 20, bottom: 60}

  @default_gamuts [:SRGB, :P3_D65]

  # Outline colour per supported working space. Callers can
  # override via the `:gamut_colours` option.
  @gamut_colours %{
    SRGB: "#60a5fa",
    P3_D65: "#22c55e",
    Rec2020: "#f59e0b",
    Adobe: "#a855f7",
    ProPhoto: "#f43f5e"
  }

  @gamut_labels %{
    SRGB: "sRGB",
    P3_D65: "Display P3",
    Rec2020: "Rec. 2020",
    Adobe: "Adobe RGB",
    ProPhoto: "ProPhoto RGB"
  }

  # Planckian annotation points — Kelvin values labelled on the
  # dashed blackbody curve.
  @planck_annotations [2000, 2700, 4000, 6500, 10000]

  # Chromaticity-space extents per projection.
  @xy_extent %{x: {0.0, 0.8}, y: {0.0, 0.9}}
  @uv_extent %{x: {0.0, 0.65}, y: {0.0, 0.6}}

  @doc """
  Renders the diagram as an SVG binary.

  ### Options

  * `:projection` is `:uv` (default) or `:xy`.

  * `:gamuts` is a list of working-space atoms to overlay as
    triangles. Default `[:SRGB, :P3_D65]`. Pass `[]` to render
    no triangles.

  * `:planckian` — when `true` (default `false`), draws the
    Planckian locus from 1500 K to 20 000 K with annotation
    points at 2000, 2700, 4000, 6500, and 10 000 K.

  * `:seed` — any `Color.input()`. When provided, a labelled
    dot is plotted at the colour's chromaticity.

  * `:palette` — a `Color.Palette.Tonal` or
    `Color.Palette.ContrastScale` struct. When provided, every
    stop is plotted as a coloured circle with a `<title>` giving
    its label and hex. The seed stop is drawn slightly larger.

  * `:width`, `:height` — SVG viewport dimensions. Defaults
    800 × 700. The inline CSS of the embedding page can scale
    this with `width: 100%`.

  * `:gamut_colours` — a map of `working_space_atom => hex`
    overriding the default outline colour for specific spaces.

  ### Returns

  * A binary containing a self-contained `<svg>…</svg>` element.

  ### Examples

      iex> svg = Color.Gamut.SVG.render(projection: :xy)
      iex> String.contains?(svg, "Chromaticity not shown directly") or String.contains?(svg, "polygon")
      true

      iex> palette = Color.Palette.Tonal.new("#3b82f6")
      iex> svg = Color.Gamut.SVG.render(palette: palette, seed: "#3b82f6")
      iex> String.contains?(svg, "<title>500:")
      true

  """
  @spec render(keyword()) :: binary()
  def render(options \\ []) do
    projection = Keyword.get(options, :projection, :uv)
    gamuts = Keyword.get(options, :gamuts, @default_gamuts)
    show_planck? = Keyword.get(options, :planckian, false)
    seed = Keyword.get(options, :seed)
    palette = Keyword.get(options, :palette)
    width = Keyword.get(options, :width, @default_width)
    height = Keyword.get(options, :height, @default_height)
    gamut_colours = Map.merge(@gamut_colours, Keyword.get(options, :gamut_colours, %{}))
    margins = @default_margins

    extent = extent_for(projection)
    transform = fn point -> to_pixel(point, projection, extent, width, height, margins) end

    locus = Diagram.spectral_locus(projection)

    planckian =
      if show_planck?, do: Diagram.planckian_locus(1500..20000//500, projection), else: []

    seed_point =
      case seed do
        nil ->
          nil

        input ->
          case Diagram.chromaticity(input, projection) do
            {:ok, point} -> point
            _ -> nil
          end
      end

    seed_hex = if seed, do: safe_hex(seed), else: nil
    palette_track = palette_track_for(palette, projection)

    triangles =
      for atom <- gamuts, Map.has_key?(@gamut_colours, atom) do
        {atom, Map.get(@gamut_labels, atom, Atom.to_string(atom)),
         Map.fetch!(gamut_colours, atom), Diagram.triangle(atom, projection)}
      end

    iodata = [
      svg_open(width, height),
      grid(extent, transform, projection),
      locus_path(locus, transform),
      axes(extent, projection, transform, width, height, margins),
      Enum.map(triangles, fn {_atom, _label, colour, tri} ->
        triangle_svg(tri, colour, transform)
      end),
      planckian_svg(planckian, transform),
      palette_svg(palette_track, transform),
      seed_svg(seed_point, seed_hex, transform),
      "</svg>"
    ]

    IO.iodata_to_binary(iodata)
  end

  # ---- palette track -----------------------------------------------------

  defp palette_track_for(nil, _projection), do: []

  defp palette_track_for(%Color.Palette.Tonal{} = palette, projection) do
    build_track(
      palette,
      projection,
      palette.seed_stop,
      palette.stops,
      Color.Palette.Tonal.labels(palette)
    )
  end

  defp palette_track_for(%Color.Palette.ContrastScale{} = palette, projection) do
    build_track(
      palette,
      projection,
      palette.seed_stop,
      palette.stops,
      Color.Palette.ContrastScale.labels(palette)
    )
  end

  defp palette_track_for(_, _), do: []

  defp build_track(_palette, projection, seed_stop, stops, labels) do
    labels
    |> Enum.map(fn label ->
      color = Map.fetch!(stops, label)

      case Diagram.chromaticity(color, projection) do
        {:ok, point} ->
          %{
            label: label,
            hex: Color.to_hex(color),
            point: point,
            is_seed: label == seed_stop
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ---- drawing helpers ---------------------------------------------------

  defp svg_open(width, height) do
    "<svg viewBox=\"0 0 #{width} #{height}\" xmlns=\"http://www.w3.org/2000/svg\">"
  end

  defp to_pixel(point, projection, extent, width, height, margins) do
    {a, b} = coords(point, projection)
    {min_x, max_x} = extent.x
    {min_y, max_y} = extent.y

    plot_w = width - margins.left - margins.right
    plot_h = height - margins.top - margins.bottom

    px = margins.left + (a - min_x) / (max_x - min_x) * plot_w
    py = margins.top + plot_h - (b - min_y) / (max_y - min_y) * plot_h
    {px, py}
  end

  defp coords(%{x: x, y: y}, :xy), do: {x, y}
  defp coords(%{u: u, v: v}, :uv), do: {u, v}

  defp extent_for(:xy), do: @xy_extent
  defp extent_for(:uv), do: @uv_extent

  defp locus_path([], _transform), do: []

  defp locus_path(points, transform) do
    d =
      points
      |> Enum.map(transform)
      |> Enum.map_join(" ", fn {px, py} -> "#{fmt(px)},#{fmt(py)}" end)

    "<polygon points=\"#{d}\" fill=\"rgba(255,255,255,0.03)\" stroke=\"#94a3b8\" stroke-width=\"1\" />"
  end

  defp triangle_svg(tri, colour, transform) do
    [r_px, g_px, b_px] = Enum.map([tri.red, tri.green, tri.blue], transform)
    pts = Enum.map_join([r_px, g_px, b_px], " ", fn {x, y} -> "#{fmt(x)},#{fmt(y)}" end)
    {wx, wy} = transform.(tri.white)

    [
      "<polygon points=\"#{pts}\" fill=\"#{colour}\" fill-opacity=\"0.08\" ",
      "stroke=\"#{colour}\" stroke-width=\"1.5\" />",
      "<circle cx=\"#{fmt(wx)}\" cy=\"#{fmt(wy)}\" r=\"4\" fill=\"#{colour}\" />"
    ]
  end

  defp planckian_svg([], _transform), do: []

  defp planckian_svg(points, transform) do
    d =
      points
      |> Enum.map(&transform.(&1))
      |> Enum.map_join(" ", fn {px, py} -> "#{fmt(px)},#{fmt(py)}" end)

    annotations =
      points
      |> Enum.filter(&(&1.kelvin in @planck_annotations))
      |> Enum.map(fn point ->
        {px, py} = transform.(point)

        [
          "<circle cx=\"#{fmt(px)}\" cy=\"#{fmt(py)}\" r=\"3\" fill=\"#fbbf24\" />",
          "<text x=\"#{fmt(px + 6)}\" y=\"#{fmt(py - 4)}\" ",
          "fill=\"#fbbf24\" font-size=\"10\" font-family=\"ui-monospace,monospace\">",
          "#{point.kelvin}K</text>"
        ]
      end)

    [
      "<polyline points=\"#{d}\" fill=\"none\" stroke=\"#fbbf24\" ",
      "stroke-width=\"1.2\" stroke-dasharray=\"3,3\" />",
      annotations
    ]
  end

  defp palette_svg([], _transform), do: []

  defp palette_svg(track, transform) do
    polyline =
      track
      |> Enum.map(&transform.(&1.point))
      |> Enum.map_join(" ", fn {px, py} -> "#{fmt(px)},#{fmt(py)}" end)

    circles =
      Enum.map(track, fn %{label: label, hex: hex, point: point, is_seed: is_seed?} ->
        {px, py} = transform.(point)
        r = if is_seed?, do: "5", else: "3.5"
        sw = if is_seed?, do: "1.5", else: "1"

        [
          "<circle cx=\"#{fmt(px)}\" cy=\"#{fmt(py)}\" r=\"#{r}\" fill=\"#{hex}\" ",
          "stroke=\"#fff\" stroke-opacity=\"0.7\" stroke-width=\"#{sw}\">",
          "<title>#{label}: #{hex}</title></circle>"
        ]
      end)

    [
      "<polyline points=\"#{polyline}\" fill=\"none\" ",
      "stroke=\"#ffffff\" stroke-opacity=\"0.35\" stroke-width=\"1\" />",
      circles
    ]
  end

  defp seed_svg(nil, _seed, _transform), do: []

  defp seed_svg(point, seed_hex, transform) do
    {px, py} = transform.(point)
    hex = seed_hex || "#000000"

    [
      "<circle cx=\"#{fmt(px)}\" cy=\"#{fmt(py)}\" r=\"7\" fill=\"#{hex}\" ",
      "stroke=\"#fff\" stroke-width=\"2\" />",
      "<text x=\"#{fmt(px + 10)}\" y=\"#{fmt(py + 4)}\" fill=\"#fff\" font-size=\"11\" ",
      "font-family=\"ui-monospace,monospace\">seed</text>"
    ]
  end

  defp axes(extent, projection, transform, width, height, _margins) do
    {min_x, max_x} = extent.x
    {min_y, max_y} = extent.y

    x_label = if projection == :xy, do: "x", else: "u′"
    y_label = if projection == :xy, do: "y", else: "v′"

    x_ticks = axis_ticks(min_x, max_x)
    y_ticks = axis_ticks(min_y, max_y)

    tick_x =
      Enum.map(x_ticks, fn value ->
        {px, py} = transform.(point_for(projection, value, min_y))

        [
          "<line x1=\"#{fmt(px)}\" y1=\"#{fmt(py)}\" x2=\"#{fmt(px)}\" y2=\"#{fmt(py + 5)}\" stroke=\"#475569\" />",
          "<text x=\"#{fmt(px)}\" y=\"#{fmt(py + 18)}\" fill=\"#94a3b8\" font-size=\"11\" ",
          "font-family=\"ui-monospace,monospace\" text-anchor=\"middle\">",
          format_tick(value),
          "</text>"
        ]
      end)

    tick_y =
      Enum.map(y_ticks, fn value ->
        {px, py} = transform.(point_for(projection, min_x, value))

        [
          "<line x1=\"#{fmt(px - 5)}\" y1=\"#{fmt(py)}\" x2=\"#{fmt(px)}\" y2=\"#{fmt(py)}\" stroke=\"#475569\" />",
          "<text x=\"#{fmt(px - 8)}\" y=\"#{fmt(py + 4)}\" fill=\"#94a3b8\" font-size=\"11\" ",
          "font-family=\"ui-monospace,monospace\" text-anchor=\"end\">",
          format_tick(value),
          "</text>"
        ]
      end)

    [
      tick_x,
      tick_y,
      "<text x=\"#{fmt(width / 2)}\" y=\"#{height - 15}\" fill=\"#e5e7eb\" ",
      "font-size=\"13\" font-family=\"ui-monospace,monospace\" text-anchor=\"middle\">",
      x_label,
      "</text>",
      "<text x=\"20\" y=\"#{fmt(height / 2)}\" fill=\"#e5e7eb\" font-size=\"13\" ",
      "font-family=\"ui-monospace,monospace\" text-anchor=\"middle\" ",
      "transform=\"rotate(-90 20 #{fmt(height / 2)})\">",
      y_label,
      "</text>"
    ]
  end

  defp grid(extent, transform, projection) do
    {min_x, max_x} = extent.x
    {min_y, max_y} = extent.y

    vertical =
      Enum.map(axis_ticks(min_x, max_x), fn v ->
        {x1, y1} = transform.(point_for(projection, v, min_y))
        {_x2, y2} = transform.(point_for(projection, v, max_y))

        "<line x1=\"#{fmt(x1)}\" y1=\"#{fmt(y1)}\" x2=\"#{fmt(x1)}\" y2=\"#{fmt(y2)}\" stroke=\"#1f2937\" stroke-width=\"0.5\" />"
      end)

    horizontal =
      Enum.map(axis_ticks(min_y, max_y), fn v ->
        {x1, y1} = transform.(point_for(projection, min_x, v))
        {x2, _y2} = transform.(point_for(projection, max_x, v))

        "<line x1=\"#{fmt(x1)}\" y1=\"#{fmt(y1)}\" x2=\"#{fmt(x2)}\" y2=\"#{fmt(y1)}\" stroke=\"#1f2937\" stroke-width=\"0.5\" />"
      end)

    [vertical, horizontal]
  end

  defp point_for(:xy, x, y), do: %{x: x, y: y}
  defp point_for(:uv, u, v), do: %{u: u, v: v}

  defp axis_ticks(min, max) do
    first = :math.ceil(min * 10) / 10
    Stream.iterate(first, &(&1 + 0.1)) |> Enum.take_while(&(&1 <= max + 1.0e-9))
  end

  defp format_tick(v), do: :erlang.float_to_binary(v * 1.0, decimals: 1)

  defp fmt(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 2)
  defp fmt(n), do: to_string(n)

  defp safe_hex(input) do
    case Color.new(input) do
      {:ok, srgb} -> Color.to_hex(srgb)
      _ -> "#000000"
    end
  rescue
    _ -> "#000000"
  end
end
