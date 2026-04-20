defmodule Color.Gamut.SVGTest do
  use ExUnit.Case, async: true

  doctest Color.Gamut.SVG

  alias Color.Gamut.SVG

  describe "render/1" do
    test "produces a complete SVG with standard xmlns" do
      svg = SVG.render()

      assert String.starts_with?(
               svg,
               "<svg viewBox=\"0 0 800 700\" xmlns=\"http://www.w3.org/2000/svg\">"
             )

      assert String.ends_with?(svg, "</svg>")
    end

    test "default gamuts are sRGB + P3" do
      svg = SVG.render()
      assert svg =~ "stroke=\"#60a5fa\""
      assert svg =~ "stroke=\"#22c55e\""
      refute svg =~ "stroke=\"#f59e0b\""
    end

    test "empty gamut list produces no triangle overlays" do
      svg = SVG.render(gamuts: [])
      refute svg =~ "stroke=\"#60a5fa\""
      refute svg =~ "stroke=\"#22c55e\""
      # Spectral locus is still there.
      assert svg =~ "<polygon"
    end

    test "projection :xy renders x / y axis labels" do
      svg = SVG.render(projection: :xy)
      assert svg =~ ~s(>x</text>)
      assert svg =~ ~s(>y</text>)
    end

    test "projection :uv renders u′ / v′ axis labels" do
      svg = SVG.render(projection: :uv)
      assert svg =~ ~s(>u′</text>)
      assert svg =~ ~s(>v′</text>)
    end

    test "planckian locus draws a dashed polyline with CCT annotations" do
      svg = SVG.render(planckian: true)
      assert svg =~ "stroke-dasharray=\"3,3\""
      assert svg =~ "6500K"
    end

    test "planckian off by default" do
      svg = SVG.render()
      refute svg =~ "stroke-dasharray=\"3,3\""
    end

    test "seed overlay plots a dot filled with the seed colour" do
      svg = SVG.render(seed: "#ff0000")
      assert svg =~ ~s(fill="#ff0000")
    end

    test "palette overlay adds a circle per stop with <title>" do
      palette = Color.Palette.Tonal.new("#3b82f6")
      svg = SVG.render(palette: palette)

      assert svg =~ ~r/<title>500: #[0-9a-f]{6}<\/title>/
      # One circle per stop label plus one extra per triangle white
      # point, plus (optionally) the seed — at minimum we should
      # see all 11 stop circles.
      circles = Regex.scan(~r/<circle /, svg) |> length()
      assert circles >= 11
    end

    test "custom width and height" do
      svg = SVG.render(width: 400, height: 300)
      assert svg =~ ~s(viewBox="0 0 400 300")
    end

    test "custom gamut colour override" do
      svg = SVG.render(gamuts: [:SRGB], gamut_colours: %{SRGB: "#123456"})
      assert svg =~ "stroke=\"#123456\""
      refute svg =~ "stroke=\"#60a5fa\""
    end

    test "ContrastScale palette also renders" do
      palette = Color.Palette.ContrastScale.new("#3b82f6")
      svg = SVG.render(palette: palette)

      # At least one stop tooltip present.
      assert svg =~ ~r/<title>\d+: #[0-9a-f]{6}<\/title>/
    end
  end
end
