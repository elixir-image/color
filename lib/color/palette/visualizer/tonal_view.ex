defmodule Color.Palette.Visualizer.TonalView do
  @moduledoc false

  alias Color.Palette.Tonal
  alias Color.Palette.Visualizer.Render

  def render(params, base) do
    seed = Map.get(params, :seed, "#3b82f6")
    hue_drift? = Map.get(params, :hue_drift, false)
    name = Map.get(params, :name)
    error = Map.get(params, :error)

    body =
      case build(seed, hue_drift?, name) do
        {:ok, palette} -> success_body(palette)
        {:error, message} -> ["<div class=\"vz-error\">", Render.escape(message), "</div>"]
      end

    Render.page(
      title: "Tonal",
      active: "tonal",
      seed: seed,
      body: body,
      error: error,
      base: base,
      extra_fields: [
        "<label><input type=\"checkbox\" name=\"hue_drift\" value=\"1\"",
        if(hue_drift?, do: " checked", else: ""),
        "> hue drift</label>"
      ]
    )
  end

  defp build(seed, hue_drift?, name) do
    options = [hue_drift: hue_drift?]
    options = if name, do: [{:name, name} | options], else: options
    {:ok, Tonal.new(seed, options)}
  rescue
    e in Color.PaletteError -> {:error, Exception.message(e)}
    _ -> {:error, "Could not parse seed colour #{inspect(seed)}"}
  end

  defp success_body(%Tonal{} = palette) do
    [
      "<section class=\"vz-section\">",
      "<h2>Tonal scale</h2>",
      Render.tonal_strip(palette),
      "</section>",
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

  defp design_tokens_export(%Tonal{} = palette) do
    palette
    |> Tonal.to_tokens()
    |> Render.pretty_json()
    |> Render.escape()
  end

  defp css_export(%Tonal{} = palette) do
    palette |> Tonal.to_css() |> Render.escape()
  end

  defp tailwind_export(%Tonal{} = palette) do
    palette |> Tonal.to_tailwind() |> Render.escape()
  end
end
