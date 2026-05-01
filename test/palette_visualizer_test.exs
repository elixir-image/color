defmodule Color.Palette.VisualizerTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  # Silence Plug.Logger's per-request debug lines while this module
  # runs — they're noisy and drown out test output. The original level
  # is restored at the end of the suite via on_exit.
  setup_all do
    Logger.put_module_level(Plug.Logger, :info)
    on_exit(fn -> Logger.delete_module_level(Plug.Logger) end)
    :ok
  end

  @opts Color.Palette.Visualizer.init([])

  describe "routing" do
    test "GET / redirects to /tonal" do
      conn = conn(:get, "/") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/tonal"]
    end

    test "GET /unknown returns 404" do
      conn = conn(:get, "/unknown") |> Color.Palette.Visualizer.call(@opts)
      assert conn.status == 404
    end

    test "serves CSS with a long cache header" do
      conn = conn(:get, "/assets/style.css") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert ["text/css" <> _] = get_resp_header(conn, "content-type")
      assert ["public, max-age=31536000, immutable"] = get_resp_header(conn, "cache-control")
      assert conn.resp_body =~ ".vz-swatch"
    end

    test "serves the logo PNG" do
      conn = conn(:get, "/assets/logo.png") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert ["image/png" <> _] = get_resp_header(conn, "content-type")
      # PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
      assert <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>> = conn.resp_body
    end
  end

  describe "tonal view" do
    test "renders default seed" do
      conn = conn(:get, "/tonal") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Tonal scale"
      assert conn.resp_body =~ "CSS custom properties"
      assert conn.resp_body =~ "Tailwind config"
    end

    test "honours the seed query param" do
      conn = conn(:get, "/tonal?seed=%23ff00aa") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      # The seed hex lands at whichever stop it snaps to.
      assert conn.resp_body =~ ~r/--color-\d+: #ff00aa/
    end

    test "honours the hue_drift flag" do
      drift =
        conn(:get, "/tonal?seed=%233b82f6&hue_drift=1") |> Color.Palette.Visualizer.call(@opts)

      flat = conn(:get, "/tonal?seed=%233b82f6") |> Color.Palette.Visualizer.call(@opts)

      assert drift.status == 200
      assert flat.status == 200
      refute drift.resp_body == flat.resp_body
    end

    test "invalid seed renders an error message, not a 500" do
      conn = conn(:get, "/tonal?seed=not-a-color") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Could not parse seed"
    end

    test "renders a <input type=color> picker with the seed's hex" do
      conn = conn(:get, "/tonal?seed=%233b82f6") |> Color.Palette.Visualizer.call(@opts)

      assert conn.resp_body =~ ~s(type="color" name="seed_picker" value="#3b82f6")
    end

    test "picker initialises to the hex of a named colour seed" do
      conn = conn(:get, "/tonal?seed=rebeccapurple") |> Color.Palette.Visualizer.call(@opts)

      # rebeccapurple = #663399
      assert conn.resp_body =~ ~s(type="color" name="seed_picker" value="#663399")
    end

    test "exports a Design Tokens JSON block" do
      conn = conn(:get, "/tonal?seed=%233b82f6") |> Color.Palette.Visualizer.call(@opts)

      assert conn.resp_body =~ "Design Tokens"
      assert conn.resp_body =~ "$type"
      assert conn.resp_body =~ "oklch"
    end
  end

  describe "seed_picker precedence" do
    # The seed always appears verbatim at its snapped stop in the
    # CSS export block, so `=~ "--color-<N>: <seed hex>"` is a
    # clean way to verify which seed was actually used.
    defp seed_in_css?(body, seed_hex) do
      body =~ ~r/--color-\d+: #{seed_hex}/
    end

    test "picker-only submit uses picker value" do
      conn =
        conn(:get, "/tonal?seed_picker=%23ff0000&seed_picker_initial=%233b82f6")
        |> Color.Palette.Visualizer.call(@opts)

      assert seed_in_css?(conn.resp_body, "#ff0000")
    end

    test "text field wins when it differs from picker initial" do
      conn =
        conn(
          :get,
          "/tonal?seed=rebeccapurple&seed_picker=%233b82f6&seed_picker_initial=%233b82f6"
        )
        |> Color.Palette.Visualizer.call(@opts)

      # rebeccapurple → #663399
      assert seed_in_css?(conn.resp_body, "#663399")
    end

    test "picker wins when text field is unchanged from picker initial" do
      conn =
        conn(
          :get,
          "/tonal?seed=%233b82f6&seed_picker=%23ff0000&seed_picker_initial=%233b82f6"
        )
        |> Color.Palette.Visualizer.call(@opts)

      assert seed_in_css?(conn.resp_body, "#ff0000")
    end

    test "falls back to default when neither is present" do
      conn = conn(:get, "/tonal") |> Color.Palette.Visualizer.call(@opts)

      assert seed_in_css?(conn.resp_body, "#3b82f6")
    end
  end

  describe "theme view" do
    test "renders default theme" do
      conn = conn(:get, "/theme") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Tonal scales"
      assert conn.resp_body =~ "Role tokens"
      assert conn.resp_body =~ "on_primary"
      assert conn.resp_body =~ "surface"
    end

    test "dark scheme" do
      light =
        conn(:get, "/theme?seed=%233b82f6&scheme=light") |> Color.Palette.Visualizer.call(@opts)

      dark =
        conn(:get, "/theme?seed=%233b82f6&scheme=dark") |> Color.Palette.Visualizer.call(@opts)

      assert light.status == 200
      assert dark.status == 200
      assert dark.resp_body =~ "Role tokens (dark)"
      assert light.resp_body =~ "Role tokens (light)"
    end

    test "unknown scheme falls back to light" do
      conn = conn(:get, "/theme?scheme=purple") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Role tokens (light)"
    end
  end

  describe "gamut view" do
    test "renders default with u'v' projection" do
      conn = conn(:get, "/gamut") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Chromaticity diagram"
      assert conn.resp_body =~ "CIE 1976 u"
      assert conn.resp_body =~ "Visible spectrum"
      # Default gamuts: sRGB and P3 visible in legend.
      assert conn.resp_body =~ "sRGB"
      assert conn.resp_body =~ "Display P3"
    end

    test "honours projection=xy" do
      conn = conn(:get, "/gamut?projection=xy") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "CIE 1931"
    end

    # The form labels always contain "sRGB", "Display P3", etc., so
    # tests look for each space's outline colour in the legend /
    # SVG: only rendered triangles carry those hex codes.
    @srgb_colour "#60a5fa"
    @p3_colour "#22c55e"
    @rec2020_colour "#f59e0b"

    test "honours gamut[] checkboxes" do
      conn =
        conn(:get, "/gamut?gamut[]=SRGB&gamut[]=Rec2020&submitted=1")
        |> Color.Palette.Visualizer.call(@opts)

      assert conn.resp_body =~ "border:1.5px solid #{@srgb_colour}"
      assert conn.resp_body =~ "border:1.5px solid #{@rec2020_colour}"
      refute conn.resp_body =~ "border:1.5px solid #{@p3_colour}"
    end

    test "all-unchecked submit renders no triangles" do
      conn =
        conn(:get, "/gamut?submitted=1")
        |> Color.Palette.Visualizer.call(@opts)

      refute conn.resp_body =~ "border:1.5px solid #{@srgb_colour}"
      refute conn.resp_body =~ "border:1.5px solid #{@p3_colour}"
    end

    test "planckian locus toggle" do
      off = conn(:get, "/gamut?submitted=1") |> Color.Palette.Visualizer.call(@opts)
      on = conn(:get, "/gamut?planckian=1&submitted=1") |> Color.Palette.Visualizer.call(@opts)

      # The SVG polyline with a dashed stroke only renders when the
      # Planckian locus is on.
      refute off.resp_body =~ "stroke-dasharray=\"3,3\""
      assert on.resp_body =~ "stroke-dasharray=\"3,3\""
    end

    test "overlay_seed plots a seed dot and adds a legend entry" do
      conn =
        conn(:get, "/gamut?overlay_seed=1&seed=%23ff0000&submitted=1")
        |> Color.Palette.Visualizer.call(@opts)

      assert conn.resp_body =~ ~s(fill="#ff0000")
      assert conn.resp_body =~ "Seed:"
    end

    test "overlay_palette plots every tonal stop as a hoverable circle" do
      conn =
        conn(:get, "/gamut?overlay_palette=1&seed=%233b82f6&submitted=1")
        |> Color.Palette.Visualizer.call(@opts)

      # Polyline connecting the stops + a <title> per circle for
      # browser tooltips. The label + hex of the 500 stop should
      # appear in one of the <title>s.
      assert conn.resp_body =~ ~s(<polyline points=)
      assert conn.resp_body =~ ~r/<title>500: #[0-9a-f]{6}<\/title>/
      assert conn.resp_body =~ "Tonal palette"
    end

    test "overlay_palette off (default) — no track rendered" do
      conn = conn(:get, "/gamut?submitted=1") |> Color.Palette.Visualizer.call(@opts)

      refute conn.resp_body =~ ~r/<title>500: #[0-9a-f]{6}<\/title>/
      refute conn.resp_body =~ "Tonal palette"
    end

    test "emits an inline SVG" do
      conn = conn(:get, "/gamut") |> Color.Palette.Visualizer.call(@opts)

      assert conn.resp_body =~ ~r/<svg[^>]*viewBox=/
      assert conn.resp_body =~ ~s(class="vz-gamut")
    end
  end

  describe "scale view (contrast-constrained tonal)" do
    test "renders default scale" do
      conn = conn(:get, "/scale") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "guarantees 4.5"
      assert conn.resp_body =~ "Pairwise contrast matrix"
    end

    test "honours ratio and apart options" do
      conn =
        conn(:get, "/scale?ratio=3&apart=300")
        |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "guarantees 3"
      assert conn.resp_body =~ "≥ 300 apart"
    end

    test "APCA metric" do
      conn =
        conn(:get, "/scale?metric=apca&ratio=60&apart=500")
        |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Lc"
    end

    test "exports CSS, Tailwind, and Design Tokens" do
      conn = conn(:get, "/scale") |> Color.Palette.Visualizer.call(@opts)

      assert conn.resp_body =~ "CSS custom properties"
      assert conn.resp_body =~ "Tailwind config"
      assert conn.resp_body =~ "Design Tokens"
      assert conn.resp_body =~ "oklch"
    end
  end

  describe "contrast view" do
    test "renders default contrast palette" do
      conn = conn(:get, "/contrast") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Matrix (WCAG 2.x)"
    end

    test "APCA metric" do
      conn = conn(:get, "/contrast?metric=apca") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Matrix (APCA W3)"
    end

    test "custom background" do
      conn = conn(:get, "/contrast?background=black") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Stops (against"
    end

    test "invalid background surfaces an error, not a 500" do
      conn =
        conn(:get, "/contrast?background=not-a-color") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Could not parse"
    end
  end

  describe "mounting via forward" do
    # Simulate `forward "/palette", ...` by setting script_name.
    defp mounted_conn(method, path) do
      conn(method, "/palette" <> path)
      |> Map.put(:script_name, ["palette"])
      |> Map.update!(:path_info, fn ["palette" | rest] -> rest end)
    end

    test "builds links with the mounted base path" do
      conn = mounted_conn(:get, "/tonal") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      assert conn.resp_body =~ ~s(href="/palette/assets/style.css")
      assert conn.resp_body =~ ~s(href="/palette/tonal?seed=)
    end

    test "root redirect respects the base path" do
      conn = mounted_conn(:get, "/") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/palette/tonal"]
    end
  end

  describe "sort view" do
    test "GET /sort renders the default palette in rainbow order" do
      conn = conn(:get, "/sort") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      # The textarea and strategy selector must be present.
      assert conn.resp_body =~ ~s(<textarea name="colors")
      assert conn.resp_body =~ ~s(name="strategy")
      # The default colour set should include both hex and
      # named-colour forms in the textarea contents.
      assert conn.resp_body =~ "#ff0000"
      assert conn.resp_body =~ "saddlebrown"
      # The sorted section header is emitted.
      assert conn.resp_body =~ ~s(>Sorted ()
    end

    test "user-supplied colors are sorted into rainbow order" do
      colors = "#0000ff\n#ff0000\n#00ff00"

      conn =
        conn(:get, "/sort?colors=" <> URI.encode_www_form(colors))
        |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      # The sorted strip should place red before green before
      # blue (primaries in rainbow order).
      sorted_section = isolate_sorted_section(conn.resp_body)
      red_at = :binary.match(sorted_section, "#ff0000") |> elem(0)
      green_at = :binary.match(sorted_section, "#00ff00") |> elem(0)
      blue_at = :binary.match(sorted_section, "#0000ff") |> elem(0)
      assert red_at < green_at
      assert green_at < blue_at
    end

    test ":lightness strategy reorders by Oklch L" do
      colors = "white\nblack\n#808080"

      conn =
        conn(
          :get,
          "/sort?strategy=lightness&colors=" <> URI.encode_www_form(colors)
        )
        |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      sorted_section = isolate_sorted_section(conn.resp_body)
      black_at = :binary.match(sorted_section, "#000000") |> elem(0)
      gray_at = :binary.match(sorted_section, "#808080") |> elem(0)
      white_at = :binary.match(sorted_section, "#ffffff") |> elem(0)
      assert black_at < gray_at
      assert gray_at < white_at
    end

    # Slice out only the "Sorted" section of the HTML body so
    # that the colours inside the textarea (which echo the raw
    # user input) don't confuse positional assertions.
    defp isolate_sorted_section(body) do
      [_, after_header] = String.split(body, ">Sorted (", parts: 2)
      [sorted_section, _] = String.split(after_header, ">Input order<", parts: 2)
      sorted_section
    end

    test "lines that look like comments are skipped" do
      colors = "# a comment\n#ff0000\n\n  \n#0000ff"
      parsed = Color.Palette.Visualizer.SortView.parse_colors(colors)

      assert Enum.map(parsed, &Color.to_hex/1) == ["#ff0000", "#0000ff"]
    end
  end

  describe "spectrum view" do
    test "GET /spectrum renders the default palette as a hue-distribution SVG" do
      conn = conn(:get, "/spectrum") |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      # Form controls and SVG container must be present.
      assert conn.resp_body =~ ~s(<textarea name="colors")
      assert conn.resp_body =~ ~s(name="bin_width")
      assert conn.resp_body =~ ~s(name="hue_origin")
      assert conn.resp_body =~ "<svg"
      # Default colour list emits at least one hex into the SVG fill.
      assert conn.resp_body =~ ~s(fill="#ff0000")
      # Both the chromatic and achromatic strips are labelled.
      assert conn.resp_body =~ ">Hue spectrum<"
      assert conn.resp_body =~ "achromatic (lightness)"
    end

    test "user-supplied colors are partitioned into chromatic and achromatic" do
      colors = "#ff0000\nwhite\nblack\n#0000ff"

      conn =
        conn(:get, "/spectrum?colors=" <> URI.encode_www_form(colors))
        |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      # Summary shows 2 chromatic and 2 achromatic.
      assert conn.resp_body =~ "Chromatic"
      assert conn.resp_body =~ "Achromatic"
      assert conn.resp_body =~ ~s(fill="#ff0000")
      assert conn.resp_body =~ ~s(fill="#0000ff")
      assert conn.resp_body =~ ~s(fill="#ffffff")
      assert conn.resp_body =~ ~s(fill="#000000")
    end

    test "empty input renders a placeholder, not a crash" do
      conn =
        conn(:get, "/spectrum?colors=" <> URI.encode_www_form(""))
        |> Color.Palette.Visualizer.call(@opts)

      assert conn.status == 200
      # Default textarea contents repopulate rather than emitting
      # the placeholder, so just check we got a sensible page.
      assert conn.resp_body =~ "<svg" or conn.resp_body =~ "Add one or more colours"
    end
  end

  describe "Standalone" do
    test "start/1 and stop/1 work end-to-end" do
      {:ok, pid} = Color.Palette.Visualizer.Standalone.start(port: 0)
      assert is_pid(pid)
      assert :ok = Color.Palette.Visualizer.Standalone.stop(pid)
    end

    test "child_spec/1 returns a valid child spec" do
      spec = Color.Palette.Visualizer.Standalone.child_spec(port: 0)

      assert %{id: Color.Palette.Visualizer.Standalone, start: {Bandit, :start_link, [_]}} = spec
    end
  end
end
