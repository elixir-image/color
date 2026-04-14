# Integrations Guide — Building Designer Tools on `Color`

This guide is for developers building design-adjacent tooling — Figma plugins, Style Dictionary transforms, Mix tasks that regenerate CSS token files from a brand colour, Phoenix LiveView dashboards for a design system, static-site generators that embed gamut diagrams, CI jobs that audit palette accessibility, and so on.

Everything the visualizer does is reachable programmatically. The visualizer is a *consumer* of the library's public API. You can generate a palette, export it in any supported format, and render a gamut diagram as SVG — all without going near a Plug router.

## The pieces

| Task | API |
|---|---|
| Generate a palette | `Color.Palette.tonal/2`, `theme/2`, `contrast/2`, `contrast_scale/2` |
| Export as CSS custom properties | `Color.Palette.Tonal.to_css/2`, `Color.Palette.ContrastScale.to_css/2` |
| Export as Tailwind config | `Color.Palette.Tonal.to_tailwind/2`, `Color.Palette.ContrastScale.to_tailwind/2` |
| Export as W3C DTCG tokens | `Color.Palette.Tonal.to_tokens/2`, `Color.Palette.Theme.to_tokens/2`, `Color.Palette.Contrast.to_tokens/2`, `Color.Palette.ContrastScale.to_tokens/2` |
| Encode JSON | `:json.encode/1` (Erlang built-in) |
| Render a gamut diagram as SVG | `Color.Gamut.SVG.render/1` |
| Get raw gamut geometry | `Color.Gamut.Diagram.spectral_locus/2`, `triangle/2`, `planckian_locus/2`, `chromaticity/2` |
| Encode / decode individual colours as DTCG | `Color.DesignTokens.encode/2`, `decode/1` |

## Generating palettes

All four algorithms take the same shape — a seed colour and an options keyword list — and return a struct.

### Tonal scale (Tailwind-style)

```elixir
palette = Color.Palette.tonal("#3b82f6", name: "blue")

# %Color.Palette.Tonal{
#   name: "blue",
#   seed: %Color.SRGB{...},
#   seed_stop: 500,
#   stops: %{50 => ..., 100 => ..., ..., 950 => ...},
#   options: [...]
# }
```

See [the palette guide](palettes.md) for the algorithm's details and when each algorithm is the right choice.

### Theme (Material Design 3 style)

```elixir
theme = Color.Palette.theme("#3b82f6")

{:ok, primary} = Color.Palette.Theme.role(theme, :primary)
{:ok, on_surface_dark} = Color.Palette.Theme.role(theme, :on_surface, scheme: :dark)
```

### Contrast (Leonardo style)

```elixir
palette = Color.Palette.contrast("#3b82f6",
  background: "white",
  targets: [3.0, 4.5, 7.0, 10.0]
)

# Each stop records the target and the achieved contrast, and
# marks unreachable targets rather than silently falling back.
```

### Contrast-constrained tonal scale

```elixir
scale = Color.Palette.contrast_scale("#3b82f6",
  guarantee: {4.5, 500}
)

# Any two stops whose labels differ by 500 or more are guaranteed
# to contrast at least 4.5:1 against each other.
```

## Exporting to CSS custom properties

```elixir
palette = Color.Palette.tonal("#3b82f6", name: "blue")
css = Color.Palette.Tonal.to_css(palette)
#=>
# :root {
#   --blue-50: #f4f9ff;
#   --blue-100: #c9deff;
#   ...
#   --blue-950: #000825;
# }

File.write!("priv/static/brand-tokens.css", css)
```

Both the declaration selector and the property name prefix are overridable:

```elixir
Color.Palette.Tonal.to_css(palette,
  selector: "[data-theme='light']",
  name: "brand"
)
#=> [data-theme='light'] {
#     --brand-50: #f4f9ff;
#     ...
```

`Color.Palette.ContrastScale.to_css/2` has the same signature.

## Exporting to Tailwind CSS

```elixir
palette = Color.Palette.tonal("#ec4899", name: "pink")
tailwind = Color.Palette.Tonal.to_tailwind(palette)
#=>
# theme: {
#   extend: {
#     colors: {
#       pink: {
#         50: "#fff1f5",
#         100: "#ffd0de",
#         ...
#       }
#     }
#   }
# }
```

Drop it into `tailwind.config.js` (or a generated wrapper) at build time:

```elixir
# Mix task: regenerate Tailwind theme from a brand colour
defmodule Mix.Tasks.Brand.Tailwind do
  use Mix.Task

  def run([hex]) do
    palette = Color.Palette.tonal(hex, name: "brand")
    config = Color.Palette.Tonal.to_tailwind(palette)

    """
    module.exports = {
      content: ["./lib/**/*.{ex,heex}"],
      #{config}
    }
    """
    |> then(&File.write!("assets/tailwind.config.js", &1))

    Mix.shell().info("Regenerated Tailwind config from #{hex}")
  end
end
```

## Exporting to W3C Design Tokens (DTCG)

All four palette types emit DTCG 2025.10 colour tokens.

```elixir
palette = Color.Palette.tonal("#3b82f6", name: "blue")
tokens = Color.Palette.Tonal.to_tokens(palette)
#=> %{
#     "blue" => %{
#       "50"  => %{"$type" => "color", "$value" => %{...}},
#       "500" => %{"$type" => "color", "$value" => %{"colorSpace" => "oklch", "components" => [...], "hex" => "#3b82f6"}},
#       ...
#     }
#   }

File.write!("tokens/blue.json", :json.encode(tokens) |> IO.iodata_to_binary())
```

The default encoded space is Oklch — richer than sRGB and the modern standard — with a `"hex"` fallback for tools that don't yet speak Oklch. Override via `:space`:

```elixir
# Emit as sRGB for a stricter downstream tool
Color.Palette.Tonal.to_tokens(palette, space: Color.SRGB)
```

For **themes**, the export emits both the five tonal sub-palettes and a `role` group with Material 3 role tokens as **DTCG alias tokens** pointing at the underlying stops — so tools that resolve aliases get both layers:

```elixir
theme = Color.Palette.theme("#3b82f6")
tokens = Color.Palette.Theme.to_tokens(theme, scheme: :light)

tokens["palette"]["primary"]["40"]
#=> %{"$type" => "color", "$value" => %{"colorSpace" => "oklch", ...}}

tokens["role"]["primary"]
#=> %{"$type" => "color", "$value" => "{palette.primary.40}"}
```

## Rendering gamut diagrams as SVG

`Color.Gamut.SVG.render/1` returns a complete, styleable SVG string — no Plug, no browser, no Chrome necessary. Drop it into HTML, paste it into a blog post, attach it to a design review.

### Basic diagram

```elixir
svg = Color.Gamut.SVG.render(projection: :uv, gamuts: [:SRGB, :P3_D65])
File.write!("gamut.svg", svg)
```

### With a palette overlay

```elixir
palette = Color.Palette.tonal("#3b82f6")

svg =
  Color.Gamut.SVG.render(
    projection: :uv,
    gamuts: [:SRGB, :P3_D65, :Rec2020],
    palette: palette,
    seed: "#3b82f6",
    planckian: true
  )
```

The palette's stops are plotted as a chain of coloured dots — each dot has a `<title>` so browsers show its label and hex on hover. Use this to verify visually that every stop in a generated palette lives inside your target display space.

### Sizing and colour overrides

```elixir
Color.Gamut.SVG.render(
  width: 400,
  height: 300,
  gamut_colours: %{SRGB: "#000", P3_D65: "#888"}
)
```

### Accessing raw geometry

If you need the points directly — to render with a different library, embed in a PDF with `ChunkyPDF`, emit as PostScript, whatever — `Color.Gamut.Diagram` returns them as plain data:

```elixir
locus = Color.Gamut.Diagram.spectral_locus(:uv, step: 10)
#=> [%{wavelength: 380.0, u: 0.2568, v: 0.0165}, ...]

sRGB_triangle = Color.Gamut.Diagram.triangle(:SRGB, :uv)
#=> %{red: %{u: ..., v: ...}, green: ..., blue: ..., white: ...}

{:ok, blue_point} = Color.Gamut.Diagram.chromaticity("#3b82f6", :uv)
```

## Decoding external Design Tokens

If you're importing a DTCG token file from Figma, Style Dictionary, or another tool, decode individual colour tokens back into `Color.*` structs:

```elixir
raw = File.read!("incoming-tokens.json") |> :json.decode()
token = raw["color"]["primary"]

case Color.DesignTokens.decode(token) do
  {:ok, %Color.Oklch{} = oklch} ->
    # use it
    Color.to_hex(oklch)

  {:error, %Color.DesignTokensDecodeError{reason: :alias_not_resolved}} ->
    # the caller has the full token tree, resolve and retry
    :needs_resolution

  {:error, e} ->
    IO.warn("unsupported: #{Exception.message(e)}")
end
```

The decoder rejects DTCG alias tokens (`{path.to.token}`) because resolving them requires the full token tree. Resolve aliases in the caller, then hand the final `$value` map here.

## A complete worked example

A Mix task that takes a brand hex, writes CSS, Tailwind, DTCG JSON, and a gamut SVG:

```elixir
defmodule Mix.Tasks.Brand.Generate do
  use Mix.Task

  @shortdoc "Regenerates brand palette artifacts from a single seed"

  def run([hex]) do
    palette = Color.Palette.tonal(hex, name: "brand")
    File.mkdir_p!("priv/brand")

    # 1. CSS custom properties
    File.write!(
      "priv/brand/brand.css",
      Color.Palette.Tonal.to_css(palette)
    )

    # 2. Tailwind config fragment
    File.write!(
      "priv/brand/brand.tailwind.js",
      Color.Palette.Tonal.to_tailwind(palette)
    )

    # 3. DTCG tokens
    tokens = Color.Palette.Tonal.to_tokens(palette)

    File.write!(
      "priv/brand/brand.tokens.json",
      :json.encode(tokens) |> IO.iodata_to_binary()
    )

    # 4. Gamut diagram showing palette coverage across common spaces
    svg =
      Color.Gamut.SVG.render(
        projection: :uv,
        gamuts: [:SRGB, :P3_D65, :Rec2020],
        palette: palette,
        seed: hex,
        planckian: true
      )

    File.write!("priv/brand/brand.gamut.svg", svg)

    Mix.shell().info("Wrote brand artifacts for #{hex}")
  end
end
```

Run it with `mix brand.generate "#3b82f6"` and you have four coordinated artefacts ready to ship.

## When to reach for what

| You're building… | Reach for |
|---|---|
| A design-token pipeline that feeds Figma / Style Dictionary | `to_tokens/2` + `:json` |
| A live theme editor for a customer-branded SaaS | `to_css/2` + LiveView |
| A Tailwind-only site with generated brand colours | `to_tailwind/2` + a Mix task |
| A documentation site for a design system | `Color.Gamut.SVG.render/1` for gamut plots + `to_tokens/2` for reference |
| A CI check that a palette stays inside sRGB | `Color.Gamut.Diagram.chromaticity/2` + a triangle containment test |
| A custom diagram renderer (PDF, PostScript, Canvas) | `Color.Gamut.Diagram.spectral_locus/2` + `triangle/2` |
| Ingesting a DTCG file from Figma | `Color.DesignTokens.decode/1` |

## Related

* [Palette guide](palettes.md) — background on the four palette algorithms.
* [Visualizer guide](visualizer.md) — the web UI this guide's APIs back.
* [`Color.Palette`](https://hexdocs.pm/color/Color.Palette.html) — palette API.
* [`Color.DesignTokens`](https://hexdocs.pm/color/Color.DesignTokens.html) — individual-colour DTCG codec.
* [`Color.Gamut.SVG`](https://hexdocs.pm/color/Color.Gamut.SVG.html) — SVG renderer.
* [`Color.Gamut.Diagram`](https://hexdocs.pm/color/Color.Gamut.Diagram.html) — raw geometric data.
