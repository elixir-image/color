defmodule Color.Palette.Visualizer.ThemeView do
  @moduledoc false

  alias Color.Palette.Theme
  alias Color.Palette.Visualizer.Render

  @role_order [
    :primary,
    :on_primary,
    :primary_container,
    :on_primary_container,
    :secondary,
    :on_secondary,
    :secondary_container,
    :on_secondary_container,
    :tertiary,
    :on_tertiary,
    :tertiary_container,
    :on_tertiary_container,
    :surface,
    :on_surface,
    :surface_variant,
    :on_surface_variant,
    :background,
    :on_background,
    :outline,
    :outline_variant
  ]

  def render(params, base) do
    seed = Map.get(params, :seed, "#3b82f6")
    scheme = Map.get(params, :scheme, :light)

    body =
      case build(seed) do
        {:ok, theme} -> success_body(theme, scheme)
        {:error, message} -> ["<div class=\"vz-error\">", Render.escape(message), "</div>"]
      end

    scheme_options = [{:light, "Light"}, {:dark, "Dark"}]

    Render.page(
      title: "Theme",
      active: "theme",
      seed: seed,
      body: body,
      base: base,
      extra_fields: [
        "<label>scheme <select name=\"scheme\">",
        Enum.map(scheme_options, fn {value, label} ->
          selected = if value == scheme, do: " selected", else: ""

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

  defp build(seed) do
    {:ok, Theme.new(seed)}
  rescue
    e in Color.PaletteError -> {:error, Exception.message(e)}
    _ -> {:error, "Could not parse seed colour #{inspect(seed)}"}
  end

  defp success_body(%Theme{} = theme, scheme) do
    [
      scales_section(theme),
      roles_section(theme, scheme),
      tokens_section(theme, scheme)
    ]
  end

  defp tokens_section(%Theme{} = theme, scheme) do
    json =
      theme
      |> Theme.to_tokens(scheme: scheme)
      |> Render.pretty_json()
      |> Render.escape()

    [
      "<section class=\"vz-section\">",
      "<h2>Design Tokens (W3C DTCG)</h2>",
      "<div class=\"vz-export\">",
      json,
      "</div>",
      "</section>"
    ]
  end

  defp scales_section(%Theme{} = theme) do
    rows = [
      {:primary, theme.primary},
      {:secondary, theme.secondary},
      {:tertiary, theme.tertiary},
      {:neutral, theme.neutral},
      {:neutral_variant, theme.neutral_variant}
    ]

    [
      "<section class=\"vz-section\">",
      "<h2>Tonal scales</h2>",
      Enum.map(rows, fn {name, palette} ->
        [
          "<div style=\"margin-bottom:16px\">",
          "<div style=\"font-size:11px;text-transform:uppercase;letter-spacing:0.08em;color:var(--vz-text-dim);margin-bottom:6px;font-weight:600\">",
          Render.escape(to_string(name)),
          "</div>",
          Render.tonal_strip(palette),
          "</div>"
        ]
      end),
      "</section>"
    ]
  end

  defp roles_section(%Theme{} = theme, scheme) do
    cards =
      Enum.map(@role_order, fn role ->
        {:ok, color} = Theme.role(theme, role, scheme: scheme)
        pair = pair_role(role)

        text_color =
          case pair do
            nil ->
              Render.text_on(color)

            pair_role ->
              case Theme.role(theme, pair_role, scheme: scheme) do
                {:ok, paired} -> Color.to_hex(paired)
                _ -> Render.text_on(color)
              end
          end

        hex = Color.to_hex(color)

        [
          "<div class=\"vz-role\" style=\"background:",
          hex,
          ";color:",
          text_color,
          "\">",
          "<div class=\"vz-role-name\">",
          Render.escape(to_string(role)),
          "</div>",
          "<div class=\"vz-role-hex\">",
          Render.escape(hex),
          "</div>",
          "</div>"
        ]
      end)

    [
      "<section class=\"vz-section\">",
      "<h2>Role tokens (",
      Atom.to_string(scheme),
      ")</h2>",
      "<div class=\"vz-roles\">",
      cards,
      "</div>",
      "</section>"
    ]
  end

  defp pair_role(:primary), do: :on_primary
  defp pair_role(:on_primary), do: :primary
  defp pair_role(:primary_container), do: :on_primary_container
  defp pair_role(:on_primary_container), do: :primary_container
  defp pair_role(:secondary), do: :on_secondary
  defp pair_role(:on_secondary), do: :secondary
  defp pair_role(:secondary_container), do: :on_secondary_container
  defp pair_role(:on_secondary_container), do: :secondary_container
  defp pair_role(:tertiary), do: :on_tertiary
  defp pair_role(:on_tertiary), do: :tertiary
  defp pair_role(:tertiary_container), do: :on_tertiary_container
  defp pair_role(:on_tertiary_container), do: :tertiary_container
  defp pair_role(:surface), do: :on_surface
  defp pair_role(:on_surface), do: :surface
  defp pair_role(:surface_variant), do: :on_surface_variant
  defp pair_role(:on_surface_variant), do: :surface_variant
  defp pair_role(:background), do: :on_background
  defp pair_role(:on_background), do: :background
  defp pair_role(_), do: nil
end
