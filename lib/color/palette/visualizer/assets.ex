defmodule Color.Palette.Visualizer.Assets do
  @moduledoc false

  # Inlined assets for the visualizer. The CSS is written inline;
  # the logo PNG is read at compile time and cached as a module
  # attribute so the visualizer works regardless of the runtime
  # working directory.

  # Compile-time path to logo.png at the project root. __ENV__.file
  # at compile time gives the absolute path to this source file, so
  # we walk up to the project root from there rather than depending
  # on the caller's working directory.
  @logo_path __ENV__.file
             |> Path.dirname()
             |> Path.join("../../../../logo.png")
             |> Path.expand()
  @external_resource @logo_path
  @logo (case File.read(@logo_path) do
           {:ok, bytes} -> bytes
           {:error, _} -> <<>>
         end)

  @spec logo_png() :: binary()
  def logo_png, do: @logo

  @css """
  :root {
    --vz-bg: #0b0d10;
    --vz-surface: #15181d;
    --vz-surface-2: #1d2127;
    --vz-border: #2a2f37;
    --vz-text: #e5e7eb;
    --vz-text-dim: #9ca3af;
    --vz-text-faint: #6b7280;
    --vz-accent: #60a5fa;
    --vz-pass: #22c55e;
    --vz-fail: #ef4444;
    --vz-warn: #f59e0b;
  }

  * { box-sizing: border-box; }

  html, body {
    margin: 0;
    padding: 0;
    background: var(--vz-bg);
    color: var(--vz-text);
    font: 14px/1.5 ui-sans-serif, system-ui, -apple-system, "Segoe UI",
          sans-serif;
  }

  body { min-height: 100vh; }

  a { color: var(--vz-accent); text-decoration: none; }
  a:hover { text-decoration: underline; }

  header.vz-header {
    position: sticky;
    top: 0;
    z-index: 10;
    background: var(--vz-surface);
    border-bottom: 1px solid var(--vz-border);
    padding: 12px 20px;
    display: flex;
    gap: 16px;
    align-items: center;
    flex-wrap: wrap;
  }

  header.vz-header h1 {
    margin: 0;
    font-size: 16px;
    font-weight: 600;
    letter-spacing: 0.01em;
  }

  a.vz-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    color: var(--vz-text);
  }
  a.vz-brand:hover { text-decoration: none; }

  img.vz-logo {
    display: block;
    width: 32px;
    height: 32px;
    border-radius: 6px;
  }

  nav.vz-tabs { display: flex; gap: 4px; }
  nav.vz-tabs a {
    padding: 6px 12px;
    border-radius: 6px;
    color: var(--vz-text-dim);
    font-weight: 500;
  }
  nav.vz-tabs a:hover { background: var(--vz-surface-2); text-decoration: none; }
  nav.vz-tabs a.active { background: var(--vz-surface-2); color: var(--vz-text); }

  form.vz-form {
    display: flex;
    gap: 8px;
    margin-left: auto;
    align-items: center;
    flex-wrap: wrap;
  }

  form.vz-form label { color: var(--vz-text-dim); font-size: 12px; }

  form.vz-form input[type="text"],
  form.vz-form select {
    background: var(--vz-bg);
    color: var(--vz-text);
    border: 1px solid var(--vz-border);
    border-radius: 6px;
    padding: 6px 10px;
    font: inherit;
    min-width: 0;
  }
  form.vz-form input[type="text"] { width: 140px; font-family: ui-monospace, monospace; }

  form.vz-form button {
    background: var(--vz-accent);
    color: #0b1220;
    border: 0;
    border-radius: 6px;
    padding: 6px 14px;
    font: inherit;
    font-weight: 600;
    cursor: pointer;
  }

  main.vz-main { padding: 24px 20px; max-width: 1400px; margin: 0 auto; }

  .vz-error {
    background: color-mix(in oklch, var(--vz-fail) 15%, transparent);
    border: 1px solid var(--vz-fail);
    border-radius: 8px;
    padding: 12px 16px;
    margin-bottom: 20px;
    color: #fecaca;
  }

  .vz-section { margin-bottom: 36px; }
  .vz-section h2 {
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--vz-text-dim);
    margin: 0 0 12px 0;
    font-weight: 600;
  }

  /* --- Tonal strip --- */
  .vz-strip { display: grid; gap: 6px; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); }

  .vz-swatch {
    border-radius: 10px;
    overflow: hidden;
    border: 1px solid var(--vz-border);
    background: var(--vz-surface);
    display: flex;
    flex-direction: column;
  }

  .vz-swatch .vz-chip {
    aspect-ratio: 1;
    display: flex;
    align-items: flex-start;
    justify-content: flex-start;
    padding: 8px;
    font-size: 11px;
    font-weight: 600;
    font-family: ui-monospace, monospace;
    position: relative;
  }

  .vz-swatch.vz-seed .vz-chip::after {
    content: "SEED";
    position: absolute;
    bottom: 8px;
    right: 8px;
    font-size: 9px;
    padding: 2px 6px;
    border-radius: 999px;
    background: rgba(0,0,0,0.35);
    color: #fff;
    letter-spacing: 0.1em;
  }

  .vz-swatch .vz-meta {
    padding: 8px 10px;
    font-size: 11px;
    line-height: 1.45;
    font-family: ui-monospace, monospace;
    color: var(--vz-text-dim);
  }

  .vz-swatch .vz-hex { color: var(--vz-text); font-weight: 600; font-size: 12px; }

  .vz-swatch .vz-contrast {
    display: flex;
    gap: 6px;
    margin-top: 4px;
    font-size: 10px;
  }
  .vz-swatch .vz-contrast span.pass { color: var(--vz-pass); }
  .vz-swatch .vz-contrast span.fail { color: var(--vz-fail); }

  /* --- Theme roles grid --- */
  .vz-roles {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: 10px;
  }
  .vz-role {
    border-radius: 10px;
    padding: 16px;
    border: 1px solid var(--vz-border);
    font-family: ui-monospace, monospace;
    font-size: 12px;
    line-height: 1.5;
  }
  .vz-role .vz-role-name { font-weight: 700; font-size: 13px; }
  .vz-role .vz-role-hex { opacity: 0.8; font-size: 11px; }

  /* --- Contrast matrix --- */
  table.vz-matrix {
    width: 100%;
    border-collapse: collapse;
    font-family: ui-monospace, monospace;
    font-size: 12px;
  }
  table.vz-matrix th,
  table.vz-matrix td {
    padding: 8px 10px;
    border-bottom: 1px solid var(--vz-border);
    text-align: left;
  }
  table.vz-matrix th {
    font-weight: 600;
    color: var(--vz-text-dim);
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  table.vz-matrix td.pass { color: var(--vz-pass); }
  table.vz-matrix td.fail { color: var(--vz-fail); }
  table.vz-matrix td.warn { color: var(--vz-warn); }
  table.vz-matrix td.unreachable { color: var(--vz-text-faint); text-decoration: line-through; }
  table.vz-matrix td.achieved { font-variant-numeric: tabular-nums; }

  /* --- Export block --- */
  .vz-export {
    background: var(--vz-surface);
    border: 1px solid var(--vz-border);
    border-radius: 10px;
    padding: 16px;
    font-family: ui-monospace, monospace;
    font-size: 12px;
    line-height: 1.6;
    white-space: pre;
    overflow-x: auto;
    color: var(--vz-text-dim);
  }
  .vz-export .comment { color: var(--vz-text-faint); }

  /* Three-column layout for stacking related export blocks side-by-side.
     Falls back to fewer columns at narrower viewports. Each column is a
     .vz-section so its h2 and .vz-export sit naturally stacked inside. */
  .vz-exports {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 20px;
    align-items: start;
  }
  .vz-exports > .vz-section { margin-bottom: 0; }
  .vz-exports > .vz-section > .vz-export { min-width: 0; }

  @media (max-width: 1100px) {
    .vz-exports { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  }
  @media (max-width: 700px) {
    .vz-exports { grid-template-columns: 1fr; }
  }

  /* --- Gamut diagram --- */
  .vz-gamut-wrapper {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 260px;
    gap: 20px;
    align-items: start;
  }
  svg.vz-gamut {
    width: 100%;
    height: auto;
    display: block;
    background: var(--vz-surface);
    border: 1px solid var(--vz-border);
    border-radius: 10px;
  }
  .vz-gamut-legend {
    background: var(--vz-surface);
    border: 1px solid var(--vz-border);
    border-radius: 10px;
    padding: 16px;
    font-size: 12px;
    line-height: 1.5;
  }
  .vz-gamut-legend h3 {
    margin: 0 0 8px 0;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--vz-text-dim);
  }
  .vz-gamut-legend ul {
    list-style: none;
    padding: 0;
    margin: 0;
  }
  .vz-gamut-legend li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 0;
  }
  .vz-legend-swatch {
    display: inline-block;
    width: 18px;
    height: 18px;
    border-radius: 4px;
    flex-shrink: 0;
  }
  @media (max-width: 900px) {
    .vz-gamut-wrapper { grid-template-columns: 1fr; }
  }

  .vz-footer {
    margin-top: 40px;
    padding: 16px 0;
    border-top: 1px solid var(--vz-border);
    color: var(--vz-text-faint);
    font-size: 12px;
    text-align: center;
  }
  """

  @spec css() :: binary()
  def css, do: @css
end
