defmodule Color.Palette.Visualizer do
  @moduledoc """
  A web-based visualizer for the palettes produced by
  `Color.Palette`.

  This module is a `Plug.Router` that can be mounted inside a
  Phoenix or Plug application, or run standalone during
  development via `Color.Palette.Visualizer.Standalone`.

  ## Three views

  * `/tonal` — [UI Colors](https://uicolors.app/) style. One seed
    becomes a row of swatches with hex, OKLCH, and contrast
    values, plus exportable CSS custom properties and Tailwind
    config.

  * `/theme` — [Material Theme Builder](https://material-foundation.github.io/material-theme-builder/)
    style. Five tonal scales and a grid of Material Design 3
    role tokens (primary / on-primary / surface / outline / …)
    for light and dark schemes.

  * `/contrast` — [Adobe Leonardo](https://leonardocolor.io/)
    style. Contrast-targeted swatches against a chosen background
    and a pass/fail matrix for common text sizes.

  All state lives in the URL — copy a URL and you've shared the
  palette.

  ## Mounting in Phoenix

  In your `router.ex`:

      forward "/palette", Color.Palette.Visualizer

  ## Running standalone

      Color.Palette.Visualizer.Standalone.start(port: 4001)

  ## Optional dependencies

  The visualizer pulls in `:plug` (required for the router) and
  `:bandit` (only used by the standalone helper). Both are
  declared `optional: true` in this library's `mix.exs`, so you
  must add them to your own project's deps to use the visualizer:

      {:plug, "~> 1.15"},
      {:bandit, "~> 1.5"}

  The core palette algorithms have no such dependency and will
  compile without either of these in place.

  """

  # Deferred compile-time check: raise at use time, not at
  # compile time of this library, so users who never touch the
  # visualizer don't need plug installed.
  if Code.ensure_loaded?(Plug.Router) do
    use Plug.Router

    plug(Plug.Logger, log: :debug)
    plug(:match)
    plug(Plug.Parsers, parsers: [:urlencoded], pass: ["text/*"])
    plug(:dispatch)

    alias Color.Palette.Visualizer.Assets
    alias Color.Palette.Visualizer.ContrastScaleView
    alias Color.Palette.Visualizer.ContrastView
    alias Color.Palette.Visualizer.ThemeView
    alias Color.Palette.Visualizer.TonalView

    get "/" do
      base = base_path(conn)

      conn
      |> Plug.Conn.put_resp_header("location", base <> "/tonal")
      |> Plug.Conn.send_resp(302, "")
    end

    get "/tonal" do
      params = parse_params(conn.params, :tonal)
      html(conn, TonalView.render(params, base_path(conn)))
    end

    get "/theme" do
      params = parse_params(conn.params, :theme)
      html(conn, ThemeView.render(params, base_path(conn)))
    end

    get "/contrast" do
      params = parse_params(conn.params, :contrast)
      html(conn, ContrastView.render(params, base_path(conn)))
    end

    get "/scale" do
      params = parse_params(conn.params, :scale)
      html(conn, ContrastScaleView.render(params, base_path(conn)))
    end

    get "/assets/style.css" do
      conn
      |> Plug.Conn.put_resp_content_type("text/css")
      |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> Plug.Conn.send_resp(200, Assets.css())
    end

    match _ do
      send_resp(conn, 404, "Not found")
    end

    # ---- helpers ---------------------------------------------------------

    defp html(conn, iodata) do
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, IO.iodata_to_binary(iodata))
    end

    # When mounted via `forward "/palette", ...`, Plug sets
    # script_name. Rebuild the base URL from it so link hrefs
    # resolve correctly whether mounted at / or at /palette.
    defp base_path(%Plug.Conn{script_name: []}), do: ""
    defp base_path(%Plug.Conn{script_name: segments}), do: "/" <> Enum.join(segments, "/")

    defp parse_params(params, :tonal) do
      %{
        seed: resolve_seed(params, "#3b82f6"),
        hue_drift: truthy?(Map.get(params, "hue_drift")),
        name: Map.get(params, "name") |> blank_default(nil)
      }
    end

    defp parse_params(params, :theme) do
      %{
        seed: resolve_seed(params, "#3b82f6"),
        scheme: atom_default(Map.get(params, "scheme"), [:light, :dark], :light)
      }
    end

    defp parse_params(params, :contrast) do
      %{
        seed: resolve_seed(params, "#3b82f6"),
        background: Map.get(params, "background") |> blank_default("white"),
        metric: atom_default(Map.get(params, "metric"), [:wcag, :apca], :wcag)
      }
    end

    defp parse_params(params, :scale) do
      %{
        seed: resolve_seed(params, "#3b82f6"),
        background: resolve_bg(params, "white"),
        metric: atom_default(Map.get(params, "metric"), [:wcag, :apca], :wcag),
        ratio: number_default(Map.get(params, "ratio"), 4.5),
        apart: number_default(Map.get(params, "apart"), 500),
        hue_drift: truthy?(Map.get(params, "hue_drift"))
      }
    end

    defp resolve_bg(params, default) do
      text = Map.get(params, "background") |> nilify_blank()
      picker = Map.get(params, "bg_picker") |> nilify_blank()
      initial = Map.get(params, "bg_picker_initial") |> nilify_blank()

      cond do
        text != nil and text != initial -> text
        picker != nil -> picker
        text != nil -> text
        true -> default
      end
    end

    defp number_default(nil, default), do: default
    defp number_default("", default), do: default

    defp number_default(value, default) when is_binary(value) do
      case Float.parse(value) do
        {f, ""} -> f
        {f, rest} when is_float(f) and byte_size(rest) <= 2 -> f
        _ -> default
      end
    end

    defp number_default(_, default), do: default

    # The form has two inputs for `seed`: the native <input
    # type="color"> (name="seed_picker") and a free-text field
    # (name="seed"). A hidden "seed_picker_initial" records what
    # the picker was pre-set to at render time.
    #
    # Precedence rule: the text field wins if it is non-empty
    # AND its value differs from the picker's initial hex. That
    # way typing `rebeccapurple` overrides the picker, but just
    # clicking the picker to change colour also works (text
    # field stayed at the initial hex, so we fall through to the
    # picker's new value).
    defp resolve_seed(params, default) do
      text = Map.get(params, "seed") |> nilify_blank()
      picker = Map.get(params, "seed_picker") |> nilify_blank()
      initial = Map.get(params, "seed_picker_initial") |> nilify_blank()

      cond do
        text != nil and text != initial -> text
        picker != nil -> picker
        text != nil -> text
        true -> default
      end
    end

    defp nilify_blank(nil), do: nil
    defp nilify_blank(""), do: nil
    defp nilify_blank(value), do: value

    defp blank_default(nil, default), do: default
    defp blank_default("", default), do: default
    defp blank_default(value, _), do: value

    defp truthy?(nil), do: false
    defp truthy?("0"), do: false
    defp truthy?("false"), do: false
    defp truthy?(_), do: true

    defp atom_default(nil, _allowed, default), do: default

    defp atom_default(value, allowed, default) when is_binary(value) do
      atom =
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError -> default
        end

      if atom in allowed, do: atom, else: default
    end

    defp atom_default(_, _, default), do: default
  else
    @compile_error "Color.Palette.Visualizer requires :plug. " <>
                     "Add `{:plug, \"~> 1.15\"}` to your project's deps."

    @doc false
    def init(_), do: raise(@compile_error)

    @doc false
    def call(_, _), do: raise(@compile_error)
  end
end
