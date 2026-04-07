defmodule Color.CSSTest do
  use ExUnit.Case, async: true

  alias Color.CSS

  describe "none keyword" do
    test "rgb(none 0 0)" do
      {:ok, c} = CSS.parse("rgb(none 0 0)")
      assert {c.r, c.g, c.b} == {+0.0, +0.0, +0.0}
    end

    test "rgb with all none channels" do
      {:ok, c} = CSS.parse("rgb(none none none)")
      assert {c.r, c.g, c.b} == {+0.0, +0.0, +0.0}
    end

    test "rgb with none alpha" do
      {:ok, c} = CSS.parse("rgb(255 0 0 / none)")
      assert c.r == 1.0
      assert c.alpha == +0.0
    end

    test "hsl with none hue" do
      {:ok, c} = CSS.parse("hsl(none 100% 50%)")
      assert c.h == +0.0
    end

    test "lab with none lightness" do
      {:ok, c} = CSS.parse("lab(none none none)")
      assert {c.l, c.a, c.b} == {+0.0, +0.0, +0.0}
    end

    test "oklch with none chroma" do
      {:ok, c} = CSS.parse("oklch(0.5 none 30)")
      assert c.l == 0.5
      assert c.c == +0.0
      assert c.h == 30.0
    end

    test "case-insensitive" do
      assert {:ok, _} = CSS.parse("rgb(NONE 0 0)")
      assert {:ok, _} = CSS.parse("rgb(None 0 0)")
    end
  end

  describe "calc()" do
    test "rgb(calc(255 / 2) 0 0)" do
      assert {:ok, c} = CSS.parse("rgb(calc(255 / 2) 0 0)")
      assert_in_delta c.r, 0.5, 0.001
    end

    test "lab with arithmetic" do
      assert {:ok, c} = CSS.parse("lab(calc(50 + 10) 0 0)")
      assert_in_delta c.l, 60.0, 0.001
    end

    test "calc with parens and precedence" do
      assert {:ok, c} = CSS.parse("rgb(calc((100 + 50) * 2 - 50) 0 0)")
      assert_in_delta c.r, 250 / 255, 0.001
    end

    test "calc with negative numbers" do
      assert {:ok, c} = CSS.parse("lab(50 calc(-30) 0)")
      assert_in_delta c.a, -30.0, 0.001
    end

    test "calc with unary plus" do
      assert {:ok, c} = CSS.parse("lab(50 calc(+30) 0)")
      assert_in_delta c.a, 30.0, 0.001
    end

    test "calc divide by zero" do
      assert {:error, _} = CSS.parse("rgb(calc(100 / 0) 0 0)")
    end
  end

  describe "device-cmyk()" do
    test "percent form" do
      assert {:ok, c} = CSS.parse("device-cmyk(0% 100% 100% 0%)")
      assert {c.c, c.m, c.y, c.k} == {+0.0, 1.0, 1.0, +0.0}
    end

    test "unit form" do
      assert {:ok, c} = CSS.parse("device-cmyk(0 1 1 0)")
      assert {c.c, c.m, c.y, c.k} == {+0.0, 1.0, 1.0, +0.0}
    end

    test "with alpha slash" do
      assert {:ok, c} = CSS.parse("device-cmyk(0 1 1 0 / 50%)")
      assert c.alpha == 0.5
    end

    test "wrong arity" do
      assert {:error, _} = CSS.parse("device-cmyk(0 1 1)")
      assert {:error, _} = CSS.parse("device-cmyk(0 1 1 0 0)")
    end

    test "round-trip" do
      cmyk = %Color.CMYK{c: 0.1, m: 0.5, y: 0.9, k: 0.0}
      css = CSS.to_css(cmyk)
      assert {:ok, parsed} = CSS.parse(css)
      assert_in_delta parsed.c, cmyk.c, 0.001
      assert_in_delta parsed.m, cmyk.m, 0.001
      assert_in_delta parsed.y, cmyk.y, 0.001
      assert_in_delta parsed.k, cmyk.k, 0.001
    end
  end

  describe "color-mix()" do
    test "midpoint in oklab" do
      assert {:ok, c} = CSS.parse("color-mix(in oklab, red, blue)")
      assert c.__struct__ == Color.Oklab
      # Sanity: should be neither red nor blue
      assert c.l > 0 and c.l < 1
    end

    test "explicit percentage on second" do
      assert {:ok, c1} = CSS.parse("color-mix(in oklab, red, blue 25%)")
      assert {:ok, c2} = CSS.parse("color-mix(in oklab, red, blue 75%)")
      # 25% blue should be redder (higher a) than 75% blue
      assert c1.a > c2.a
    end

    test "explicit percentage on first" do
      assert {:ok, c1} = CSS.parse("color-mix(in oklab, red 75%, blue)")
      assert {:ok, c2} = CSS.parse("color-mix(in oklab, red 25%, blue)")
      assert c1.a > c2.a
    end

    test "in srgb" do
      assert {:ok, c} = CSS.parse("color-mix(in srgb, red, blue)")
      assert c.__struct__ == Color.SRGB
      assert_in_delta c.r, 0.5, 0.001
      assert_in_delta c.b, 0.5, 0.001
    end

    test "in lab" do
      assert {:ok, c} = CSS.parse("color-mix(in lab, red, blue)")
      assert c.__struct__ == Color.Lab
    end

    test "in oklch with cylindrical hue" do
      assert {:ok, c} = CSS.parse("color-mix(in oklch, red, blue)")
      assert c.__struct__ == Color.Oklch
    end

    test "in hsl" do
      assert {:ok, c} = CSS.parse("color-mix(in hsl, red, blue)")
      assert c.__struct__ == Color.Hsl
    end

    test "with hex colors" do
      assert {:ok, c} = CSS.parse("color-mix(in oklab, #ff0000, #0000ff)")
      assert c.__struct__ == Color.Oklab
    end

    test "with nested function colors" do
      assert {:ok, c} = CSS.parse("color-mix(in oklab, rgb(255 0 0), rgb(0 0 255))")
      assert c.__struct__ == Color.Oklab
    end

    test "unknown space" do
      assert {:error, _} = CSS.parse("color-mix(in nonsense, red, blue)")
    end

    test "wrong arg count" do
      assert {:error, _} = CSS.parse("color-mix(in oklab, red)")
      assert {:error, _} = CSS.parse("color-mix(in oklab)")
    end

    test "missing in keyword" do
      assert {:error, _} = CSS.parse("color-mix(oklab, red, blue)")
    end
  end

  describe "relative color syntax" do
    test "rgb(from red r g b) is the same color" do
      assert {:ok, c} = CSS.parse("rgb(from red r g b)")
      assert_in_delta c.r, 1.0, 0.001
      assert_in_delta c.g, 0.0, 0.001
      assert_in_delta c.b, 0.0, 0.001
    end

    test "rgb(from red 0 g b) zeroes red channel" do
      assert {:ok, c} = CSS.parse("rgb(from red 0 g b)")
      assert_in_delta c.r, 0.0, 0.001
    end

    test "swapping channels" do
      assert {:ok, c} = CSS.parse("rgb(from red b g r)")
      assert_in_delta c.r, 0.0, 0.001
      assert_in_delta c.b, 1.0, 0.001
    end

    test "calc() referencing component" do
      assert {:ok, c} = CSS.parse("oklch(from red calc(l + 0.1) c h)")
      assert {:ok, src} = CSS.parse("red")
      {:ok, src_oklch} = Color.convert(src, Color.Oklch)
      assert_in_delta c.l, src_oklch.l + 0.1, 0.001
      assert_in_delta c.c, src_oklch.c, 0.001
    end

    test "hsl from named color" do
      assert {:ok, c} = CSS.parse("hsl(from rebeccapurple h s l)")
      assert {:ok, src_hsl} = Color.convert(%Color.SRGB{r: 0.4, g: 0.2, b: 0.6}, Color.Hsl)
      assert_in_delta c.h, src_hsl.h, 0.001
    end

    test "lab from hex" do
      assert {:ok, c} = CSS.parse("lab(from #ff0000 l a b)")
      assert {:ok, src_lab} = Color.convert(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0}, Color.Lab)
      assert_in_delta c.l, src_lab.l, 0.5
    end

    test "alpha can be referenced" do
      assert {:ok, c} = CSS.parse("rgb(from rgb(100 50 25 / 50%) r g b / alpha)")
      assert_in_delta c.alpha, 0.5, 0.001
    end

    test "calc(alpha * 2) clamped or kept" do
      assert {:ok, c} = CSS.parse("rgb(from rgb(0 0 0 / 25%) 0 0 0 / calc(alpha * 2))")
      assert_in_delta c.alpha, 0.5, 0.001
    end

    test "missing source color is an error" do
      assert {:error, _} = CSS.parse("rgb(from)")
    end
  end

  describe "hex token (regression)" do
    test "hex still parses outside functions" do
      assert {:ok, c} = CSS.parse("#ff0000")
      assert {c.r, c.g, c.b} == {1.0, +0.0, +0.0}
    end
  end

  describe "named colors" do
    test "named color via parse" do
      assert {:ok, %Color.SRGB{}} = CSS.parse("rebeccapurple")
    end
  end

  describe "to_css for CMYK" do
    test "round trips" do
      cmyk = %Color.CMYK{c: 0.0, m: 1.0, y: 1.0, k: 0.0}
      assert "device-cmyk(0% 100% 100% 0%)" = CSS.to_css(cmyk)
    end
  end
end
