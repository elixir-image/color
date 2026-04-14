defmodule Color.Palette.Visualizer.ContrastView do
  @moduledoc false

  alias Color.Palette.Contrast
  alias Color.Palette.Visualizer.Render

  def render(params, base) do
    seed = Map.get(params, :seed, "#3b82f6")
    bg = Map.get(params, :background, "white")
    metric = Map.get(params, :metric, :wcag)

    body =
      case build(seed, bg, metric) do
        {:ok, palette} -> success_body(palette, metric)
        {:error, message} -> ["<div class=\"vz-error\">", Render.escape(message), "</div>"]
      end

    metric_options = [{:wcag, "WCAG"}, {:apca, "APCA"}]

    Render.page(
      title: "Contrast",
      active: "contrast",
      seed: seed,
      body: body,
      base: base,
      extra_fields: [
        "<label>bg <input type=\"text\" name=\"background\" value=\"",
        Render.escape(bg),
        "\"></label>",
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
        "</select></label>"
      ]
    )
  end

  defp build(seed, bg, metric) do
    {:ok, Contrast.new(seed, background: bg, metric: metric)}
  rescue
    e in Color.PaletteError -> {:error, Exception.message(e)}
    _ -> {:error, "Could not parse seed or background colour"}
  end

  defp success_body(%Contrast{} = palette, metric) do
    [swatches_section(palette, metric), matrix_section(palette, metric)]
  end

  defp swatches_section(%Contrast{} = palette, metric) do
    cells =
      Enum.map(palette.stops, fn stop ->
        case stop do
          %{color: :unreachable, target: t} ->
            [
              "<div class=\"vz-swatch\"><div class=\"vz-chip\" style=\"background:var(--vz-surface-2);color:var(--vz-text-faint)\">",
              Render.fmt(t, 1),
              "</div>",
              "<div class=\"vz-meta\"><div class=\"vz-hex\">unreachable</div>target ",
              Render.fmt(t, 2),
              "</div></div>"
            ]

          %{color: color, target: t, achieved: a} ->
            hex = Color.to_hex(color)
            text_color = Render.text_on(color)

            [
              "<div class=\"vz-swatch\"><div class=\"vz-chip\" style=\"background:",
              hex,
              ";color:",
              text_color,
              "\">",
              Render.fmt(t, 1),
              "</div>",
              "<div class=\"vz-meta\"><div class=\"vz-hex\">",
              Render.escape(hex),
              "</div>target ",
              Render.fmt(t, 2),
              "<br>got ",
              Render.fmt(a, 2),
              " ",
              metric_suffix(metric),
              "</div></div>"
            ]
        end
      end)

    [
      "<section class=\"vz-section\">",
      "<h2>Stops (against ",
      Render.escape(inspect(palette.background)),
      ")</h2>",
      "<div class=\"vz-strip\">",
      cells,
      "</div>",
      "</section>"
    ]
  end

  defp matrix_section(%Contrast{} = palette, metric) do
    sizes = common_text_sizes(metric)
    bg = palette.background

    rows =
      Enum.map(palette.stops, fn stop ->
        case stop do
          %{color: :unreachable, target: t} ->
            [
              "<tr><td>",
              Render.fmt(t, 2),
              "</td>",
              Enum.map(sizes, fn _ -> "<td class=\"unreachable\">—</td>" end),
              "</tr>"
            ]

          %{color: color, target: t, achieved: a} ->
            [
              "<tr><td>",
              Render.fmt(t, 2),
              " (got ",
              Render.fmt(a, 2),
              ")</td>",
              Enum.map(sizes, fn {_label, threshold} ->
                class = if a >= threshold, do: "pass", else: "fail"
                symbol = if a >= threshold, do: "✓", else: "✗"

                [
                  "<td class=\"",
                  class,
                  "\"><span style=\"background:",
                  Color.to_hex(color),
                  ";color:",
                  Color.to_hex(bg),
                  ";padding:2px 6px;border-radius:4px;margin-right:6px\">Aa</span>",
                  symbol,
                  "</td>"
                ]
              end),
              "</tr>"
            ]
        end
      end)

    [
      "<section class=\"vz-section\">",
      "<h2>Matrix (",
      metric_label(metric),
      ")</h2>",
      "<table class=\"vz-matrix\"><thead><tr><th>Target</th>",
      Enum.map(sizes, fn {label, threshold} ->
        ["<th>", Render.escape(label), " (≥", Render.fmt(threshold, 1), ")</th>"]
      end),
      "</tr></thead><tbody>",
      rows,
      "</tbody></table>",
      "</section>"
    ]
  end

  defp metric_label(:wcag), do: "WCAG 2.x"
  defp metric_label(:apca), do: "APCA W3"
  defp metric_suffix(:wcag), do: ":1"
  defp metric_suffix(:apca), do: "Lc"

  defp common_text_sizes(:wcag) do
    [
      {"Large text", 3.0},
      {"AA body", 4.5},
      {"AAA body", 7.0},
      {"Critical", 10.0}
    ]
  end

  defp common_text_sizes(:apca) do
    [
      {"Large", 45.0},
      {"Body", 60.0},
      {"Fluent", 75.0},
      {"Max", 90.0}
    ]
  end
end
