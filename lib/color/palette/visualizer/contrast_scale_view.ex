defmodule Color.Palette.Visualizer.ContrastScaleView do
  @moduledoc false

  alias Color.Palette.ContrastScale
  alias Color.Palette.Visualizer.Render

  def render(params, base) do
    seed = Map.get(params, :seed, "#3b82f6")
    bg = Map.get(params, :background, "white")
    metric = Map.get(params, :metric, :wcag)
    ratio = Map.get(params, :ratio, 4.5)
    apart = Map.get(params, :apart, 500)
    hue_drift? = Map.get(params, :hue_drift, false)

    body =
      case build(seed, bg, metric, ratio, apart, hue_drift?) do
        {:ok, palette} -> success_body(palette, metric)
        {:error, message} -> ["<div class=\"vz-error\">", Render.escape(message), "</div>"]
      end

    metric_options = [{:wcag, "WCAG"}, {:apca, "APCA"}]

    Render.page(
      title: "Scale",
      active: "scale",
      seed: seed,
      body: body,
      base: base,
      extra_fields: [
        "<label>bg <input type=\"color\" name=\"bg_picker\" value=\"",
        Render.escape(Render.resolve_hex(bg, "#ffffff")),
        "\"> <input type=\"text\" name=\"background\" value=\"",
        Render.escape(bg),
        "\"></label>",
        "<input type=\"hidden\" name=\"bg_picker_initial\" value=\"",
        Render.escape(Render.resolve_hex(bg, "#ffffff")),
        "\">",
        "<label>ratio <input type=\"number\" step=\"0.1\" name=\"ratio\" value=\"",
        Render.escape(format_number(ratio)),
        "\" style=\"width:70px\"></label>",
        "<label>apart <input type=\"number\" step=\"50\" name=\"apart\" value=\"",
        Render.escape(Integer.to_string(round(apart))),
        "\" style=\"width:80px\"></label>",
        "<label>metric <select name=\"metric\">",
        Enum.map(metric_options, fn {value, label} ->
          selected = if value == metric, do: " selected", else: ""

          [
            "<option value=\"",
            Atom.to_string(value),
            "\"",
            selected,
            ">",
            label,
            "</option>"
          ]
        end),
        "</select></label>",
        "<label><input type=\"checkbox\" name=\"hue_drift\" value=\"1\"",
        if(hue_drift?, do: " checked", else: ""),
        "> hue drift</label>"
      ]
    )
  end

  defp build(seed, bg, metric, ratio, apart, hue_drift?) do
    palette =
      ContrastScale.new(seed,
        background: bg,
        metric: metric,
        guarantee: {ratio, apart},
        hue_drift: hue_drift?
      )

    {:ok, palette}
  rescue
    e in Color.PaletteError -> {:error, Exception.message(e)}
    _ -> {:error, "Could not parse seed or background colour"}
  end

  defp success_body(%ContrastScale{} = palette, metric) do
    [
      scale_section(palette, metric),
      matrix_section(palette, metric),
      exports_section(palette)
    ]
  end

  defp exports_section(%ContrastScale{} = palette) do
    [
      "<div class=\"vz-exports\">",
      "<section class=\"vz-section\">",
      "<h2>CSS custom properties</h2>",
      "<div class=\"vz-export\">",
      css_export(palette),
      "</div>",
      "</section>",
      "<section class=\"vz-section\">",
      "<h2>Tailwind config</h2>",
      "<div class=\"vz-export\">",
      tailwind_export(palette),
      "</div>",
      "</section>",
      "<section class=\"vz-section\">",
      "<h2>Design Tokens (W3C DTCG)</h2>",
      "<div class=\"vz-export\">",
      design_tokens_export(palette),
      "</div>",
      "</section>",
      "</div>"
    ]
  end

  defp css_export(%ContrastScale{} = palette) do
    palette |> ContrastScale.to_css() |> Render.escape()
  end

  defp tailwind_export(%ContrastScale{} = palette) do
    palette |> ContrastScale.to_tailwind() |> Render.escape()
  end

  defp design_tokens_export(%ContrastScale{} = palette) do
    palette
    |> ContrastScale.to_tokens()
    |> Render.pretty_json()
    |> Render.escape()
  end

  defp scale_section(%ContrastScale{} = palette, metric) do
    labels = ContrastScale.labels(palette)

    cells =
      Enum.map(labels, fn label ->
        color = Map.fetch!(palette.stops, label)
        achieved = Map.fetch!(palette.achieved, label)
        hex = Color.to_hex(color)
        text_color = Render.text_on(color)
        seed_class = if label == palette.seed_stop, do: " vz-seed", else: ""

        [
          "<div class=\"vz-swatch",
          seed_class,
          "\">",
          "<div class=\"vz-chip\" style=\"background:",
          hex,
          ";color:",
          text_color,
          "\">",
          Integer.to_string(label),
          "</div>",
          "<div class=\"vz-meta\"><div class=\"vz-hex\">",
          Render.escape(hex),
          "</div>vs bg: ",
          Render.fmt(achieved, 2),
          " ",
          metric_suffix(metric),
          "</div></div>"
        ]
      end)

    {ratio, apart} = palette.guarantee

    [
      "<section class=\"vz-section\">",
      "<h2>Scale — guarantees ",
      Render.fmt(ratio, 1),
      " ",
      metric_suffix(metric),
      " at ≥ ",
      Integer.to_string(round(apart)),
      " apart</h2>",
      "<div class=\"vz-strip\">",
      cells,
      "</div>",
      "</section>"
    ]
  end

  # Pairwise contrast matrix: row and column both iterate over
  # all stops, cell is the contrast between the two.
  defp matrix_section(%ContrastScale{} = palette, _metric) do
    labels = ContrastScale.labels(palette)
    {target_ratio, apart} = palette.guarantee

    header =
      [
        "<tr><th></th>",
        Enum.map(labels, fn label ->
          ["<th>", Integer.to_string(label), "</th>"]
        end),
        "</tr>"
      ]

    rows =
      Enum.map(labels, fn row_label ->
        row_color = Map.fetch!(palette.stops, row_label)

        [
          "<tr><th>",
          Integer.to_string(row_label),
          "</th>",
          Enum.map(labels, fn col_label ->
            col_color = Map.fetch!(palette.stops, col_label)
            contrast = Color.Contrast.wcag_ratio(row_color, col_color)
            distance = abs(col_label - row_label)
            expect_pass? = distance >= apart

            class =
              cond do
                distance == 0 -> "unreachable"
                expect_pass? and contrast >= target_ratio - 0.05 -> "pass"
                expect_pass? -> "fail"
                contrast >= target_ratio - 0.05 -> "pass"
                true -> ""
              end

            [
              "<td class=\"",
              class,
              " achieved\">",
              if(distance == 0, do: "—", else: Render.fmt(contrast, 1)),
              "</td>"
            ]
          end),
          "</tr>"
        ]
      end)

    [
      "<section class=\"vz-section\">",
      "<h2>Pairwise contrast matrix</h2>",
      "<p style=\"color:var(--vz-text-dim);font-size:12px;margin:0 0 12px 0\">",
      "Each cell is WCAG contrast between the row and column stops. ",
      "Green cells at ≥ ",
      Integer.to_string(round(apart)),
      " apart prove the invariant holds; any red cell at that distance would be a violation.",
      "</p>",
      "<table class=\"vz-matrix\"><thead>",
      header,
      "</thead><tbody>",
      rows,
      "</tbody></table>",
      "</section>"
    ]
  end

  defp metric_suffix(:wcag), do: ":1"
  defp metric_suffix(:apca), do: "Lc"

  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, [:short])
end
