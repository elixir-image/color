defmodule ColorTest do
  use ExUnit.Case

  doctest Color
  doctest Color.Conversion.Lindbloom
  doctest Color.Tristimulus
  doctest Color.Lab
  doctest Color.LCHab
  doctest Color.Luv
  doctest Color.LCHuv
  doctest Color.Oklab
  doctest Color.Oklch
  doctest Color.Conversion.Oklab
  doctest Color.XYY
  doctest Color.SRGB
  doctest Color.AdobeRGB
  doctest Color.RGB
  doctest Color.Hsl
  doctest Color.Hsv
  doctest Color.RGB.WorkingSpace
  doctest Color.Distance
  doctest Color.CMYK
  doctest Color.HSLuv
  doctest Color.HPLuv
  doctest Color.YCbCr
  doctest Color.JzAzBz
  doctest Color.ICtCp
  doctest Color.IPT
  doctest Color.CAM16UCS
  doctest Color.CSSNames

  if Version.match?(System.version(), ">= 1.15.0") do
    doctest Color.Sigil

    describe "~COLOR sigil" do
      import Color.Sigil

      test "hex literal" do
        assert ~COLOR[#ff0000] == %Color.SRGB{r: 1.0, g: 0.0, b: 0.0, alpha: nil}
      end

      test "css named color" do
        assert ~COLOR[rebeccapurple] ==
                 %Color.SRGB{r: 102 / 255, g: 51 / 255, b: 153 / 255, alpha: nil}
      end

      test "unit-range sRGB" do
        assert ~COLOR[1.0, 0.5, 0.0]r == %Color.SRGB{r: 1.0, g: 0.5, b: 0.0, alpha: nil}
      end

      test "byte-range sRGB" do
        byte = ~COLOR[255, 128, 0]b
        assert byte.r == 1.0
        assert_in_delta byte.g, 0.502, 1.0e-3
        assert byte.b == 0.0
      end

      test "Lab, Oklab, XYZ, HSL, HSV, CMYK" do
        assert %Color.Lab{l: 53.24, a: 80.09} = ~COLOR[53.24, 80.09, 67.20]l
        assert %Color.Oklab{l: 0.63} = ~COLOR[0.63, 0.22, 0.13]o
        assert %Color.XYZ{y: 1.0, illuminant: :D65} = ~COLOR[0.95, 1.0, 1.08]x
        assert %Color.Hsl{h: 0.5} = ~COLOR[0.5, 1.0, 0.5]h
        assert %Color.Hsv{v: 1.0} = ~COLOR[0.5, 1.0, 1.0]v
        assert %Color.CMYK{k: +0.0} = ~COLOR[0.0, 0.5, 1.0, 0.0]k
      end
    end
  end

  describe "any-to-any dispatch" do
    @srgb %Color.SRGB{r: 0.7, g: 0.5, b: 0.3, alpha: 1.0}

    @targets [
      Color.XYZ,
      Color.XYY,
      Color.Lab,
      Color.LCHab,
      Color.Luv,
      Color.LCHuv,
      Color.Oklab,
      Color.Oklch,
      Color.HSLuv,
      Color.HPLuv,
      Color.CMYK,
      Color.YCbCr,
      Color.JzAzBz,
      Color.ICtCp,
      Color.IPT,
      Color.CAM16UCS,
      Color.SRGB,
      Color.AdobeRGB,
      Color.Hsl,
      Color.Hsv
    ]

    test "round-trip sRGB -> target -> sRGB is identity for every target" do
      for target <- @targets do
        delta =
          cond do
            # Oklab / Oklch / JzAzBz / ICtCp / IPT / CAM16 all involve
            # published matrices rounded to ~10 decimals, or a
            # non-linearity that loses a few bits of precision.
            target in [
              Color.Oklab,
              Color.Oklch,
              Color.JzAzBz,
              Color.ICtCp,
              Color.IPT,
              Color.CAM16UCS
            ] ->
              1.0e-4

            # HSLuv / HPLuv round-trip through gamut calculations; also ~1e-6.
            target in [Color.HSLuv, Color.HPLuv] ->
              1.0e-6

            true ->
              1.0e-10
          end

        {:ok, converted} = Color.convert(@srgb, target)
        {:ok, back} = Color.convert(converted, Color.SRGB)

        assert_in_delta back.r, @srgb.r, delta, "#{inspect(target)} r channel"
        assert_in_delta back.g, @srgb.g, delta, "#{inspect(target)} g channel"
        assert_in_delta back.b, @srgb.b, delta, "#{inspect(target)} b channel"
      end
    end

    test "round-trip through linear Color.RGB (sRGB working space)" do
      {:ok, lin} = Color.convert(@srgb, Color.RGB, :SRGB)
      {:ok, back} = Color.convert(lin, Color.SRGB)
      assert_in_delta back.r, @srgb.r, 1.0e-10
      assert_in_delta back.g, @srgb.g, 1.0e-10
      assert_in_delta back.b, @srgb.b, 1.0e-10
    end

    test "Lab D50 round-trip preserves illuminant" do
      lab = %Color.Lab{l: 60.0, a: 20.0, b: -15.0, illuminant: :D50}
      {:ok, xyz} = Color.Lab.to_xyz(lab)
      assert xyz.illuminant == :D50
      {:ok, back} = Color.Lab.from_xyz(xyz)
      assert back.illuminant == :D50
      assert_in_delta back.l, 60.0, 1.0e-10
      assert_in_delta back.a, 20.0, 1.0e-10
      assert_in_delta back.b, -15.0, 1.0e-10
    end

    test "Color.RGB target without working space returns an error" do
      assert {:error, _} = Color.convert(@srgb, Color.RGB)
    end
  end

  describe "Color.new/1 and bare-list inputs" do
    test "new/1 from 3-element list creates sRGB with nil alpha" do
      assert {:ok, c} = Color.new([1.0, 0.5, 0.0])
      assert c.r == 1.0
      assert c.g == 0.5
      assert c.b == +0.0
      assert c.alpha == nil
    end

    test "new/1 from 4-element list preserves alpha" do
      assert {:ok, c} = Color.new([1.0, 0.5, 0.0, 0.75])
      assert c.r == 1.0
      assert c.g == 0.5
      assert c.b == +0.0
      assert c.alpha == 0.75
    end

    test "new/1 from hex string" do
      assert {:ok, c} = Color.new("#ff0000")
      assert c.r == 1.0
      assert c.g == +0.0
      assert c.b == +0.0
    end

    test "new/1 from named color" do
      assert {:ok, %Color.SRGB{}} = Color.new("rebeccapurple")
    end

    test "new/1 passes structs through" do
      c = %Color.Lab{l: 50.0, a: 20.0, b: -10.0}
      assert {:ok, ^c} = Color.new(c)
    end

    test "convert/2 accepts a bare list and assumes sRGB" do
      {:ok, a} = Color.convert([1.0, 0.0, 0.0], Color.Lab)
      {:ok, b} = Color.convert(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0}, Color.Lab)
      assert a == b
    end

    test "convert/2 accepts a hex string" do
      {:ok, lab} = Color.convert("#ff0000", Color.Lab)
      assert_in_delta lab.l, 53.24, 1.0e-2
    end

    test "convert/3 accepts a list for Color.RGB target" do
      {:ok, rgb} = Color.convert([1.0, 1.0, 1.0], Color.RGB, :SRGB)
      assert_in_delta rgb.r, 1.0, 1.0e-10
      assert_in_delta rgb.g, 1.0, 1.0e-10
      assert_in_delta rgb.b, 1.0, 1.0e-10
    end
  end

  describe "alpha preservation" do
    @srgb_with_alpha %Color.SRGB{r: 0.7, g: 0.5, b: 0.3, alpha: 0.42}

    @targets [
      Color.XYZ,
      Color.XYY,
      Color.Lab,
      Color.LCHab,
      Color.Luv,
      Color.LCHuv,
      Color.Oklab,
      Color.Oklch,
      Color.HSLuv,
      Color.HPLuv,
      Color.CMYK,
      Color.YCbCr,
      Color.JzAzBz,
      Color.ICtCp,
      Color.IPT,
      Color.CAM16UCS,
      Color.SRGB,
      Color.AdobeRGB,
      Color.Hsl,
      Color.Hsv
    ]

    test "every target preserves alpha through convert/2" do
      for target <- @targets do
        {:ok, converted} = Color.convert(@srgb_with_alpha, target)

        assert converted.alpha == 0.42,
               "#{inspect(target)} dropped alpha: got #{inspect(converted.alpha)}"
      end
    end

    test "Color.RGB (linear) preserves alpha through convert/3" do
      {:ok, rgb} = Color.convert(@srgb_with_alpha, Color.RGB, :SRGB)
      assert rgb.alpha == 0.42
    end

    test "bare list with alpha preserves alpha into any target" do
      for target <- @targets do
        {:ok, converted} = Color.convert([0.7, 0.5, 0.3, 0.42], target)
        assert converted.alpha == 0.42, "#{inspect(target)} dropped list alpha"
      end
    end

    test "chromatic adaptation preserves alpha" do
      xyz = %Color.XYZ{
        x: 0.5,
        y: 0.5,
        z: 0.5,
        alpha: 0.33,
        illuminant: :D50,
        observer_angle: 2
      }

      {:ok, adapted} = Color.XYZ.adapt(xyz, :D65)
      assert adapted.alpha == 0.33
    end
  end

  describe "premultiplied alpha" do
    test "premultiply/1 scales sRGB channels by alpha" do
      c = %Color.SRGB{r: 1.0, g: 0.5, b: 0.25, alpha: 0.5}
      assert %Color.SRGB{r: 0.5, g: 0.25, b: 0.125, alpha: 0.5} = Color.premultiply(c)
    end

    test "premultiply/1 with nil alpha is identity" do
      c = %Color.SRGB{r: 1.0, g: 0.5, b: 0.25, alpha: nil}
      assert Color.premultiply(c) == c
    end

    test "premultiply then unpremultiply is identity (alpha > 0)" do
      c = %Color.SRGB{r: 0.7, g: 0.5, b: 0.3, alpha: 0.42}
      back = c |> Color.premultiply() |> Color.unpremultiply()
      assert_in_delta back.r, c.r, 1.0e-10
      assert_in_delta back.g, c.g, 1.0e-10
      assert_in_delta back.b, c.b, 1.0e-10
      assert back.alpha == c.alpha
    end

    test "unpremultiply/1 with zero alpha is identity" do
      c = %Color.SRGB{r: 0.0, g: 0.0, b: 0.0, alpha: 0.0}
      assert Color.unpremultiply(c) == c
    end

    test "premultiply/1 raises for non-RGB color spaces" do
      assert_raise ArgumentError, fn ->
        Color.premultiply(%Color.Lab{l: 50.0, a: 20.0, b: -10.0, alpha: 0.5})
      end
    end

    test "premultiply/1 works on linear Color.RGB" do
      c = %Color.RGB{r: 1.0, g: 0.5, b: 0.25, alpha: 0.5, working_space: :SRGB}
      assert %Color.RGB{r: 0.5, g: 0.25, b: 0.125, alpha: 0.5, working_space: :SRGB} =
               Color.premultiply(c)
    end
  end

  describe "chromatic adaptation" do
    # Lindbloom's published Bradford D50 -> D65 of his D50 reference
    # white should equal his D65 reference white:
    #   D50 (0.96422, 1.0, 0.82521) -> D65 (0.95047, 1.0, 1.08883).
    test "Bradford adapts D50 white to D65 white" do
      d50 = %Color.XYZ{x: 0.96422, y: 1.0, z: 0.82521, illuminant: :D50, observer_angle: 2}
      {:ok, d65} = Color.XYZ.adapt(d50, :D65)
      assert_in_delta d65.x, 0.95047, 1.0e-5
      assert_in_delta d65.y, 1.0, 1.0e-5
      assert_in_delta d65.z, 1.08883, 1.0e-5
      assert d65.illuminant == :D65
    end

    test "Bradford round-trips D50 -> D65 -> D50 within 1e-6" do
      d50_in = %Color.XYZ{x: 0.5, y: 0.4, z: 0.3, illuminant: :D50, observer_angle: 2}
      {:ok, d65} = Color.XYZ.adapt(d50_in, :D65)
      {:ok, d50_out} = Color.XYZ.adapt(d65, :D50)
      assert_in_delta d50_out.x, d50_in.x, 1.0e-6
      assert_in_delta d50_out.y, d50_in.y, 1.0e-6
      assert_in_delta d50_out.z, d50_in.z, 1.0e-6
    end

    test "every supported adaptation method round-trips D50 <-> D65" do
      for method <- [:xyz_scaling, :bradford, :von_kries, :sharp, :cmccat2000, :cat02] do
        d50_in = %Color.XYZ{x: 0.5, y: 0.4, z: 0.3, illuminant: :D50, observer_angle: 2}
        {:ok, d65} = Color.XYZ.adapt(d50_in, :D65, method: method)
        {:ok, d50_out} = Color.XYZ.adapt(d65, :D50, method: method)
        assert_in_delta d50_out.x, d50_in.x, 1.0e-4, "#{method} x"
        assert_in_delta d50_out.y, d50_in.y, 1.0e-4, "#{method} y"
        assert_in_delta d50_out.z, d50_in.z, 1.0e-4, "#{method} z"
      end
    end

    test "Color.convert auto-adapts for D65-locked targets" do
      # The same Lab triple under D50 vs D65 should produce DIFFERENT
      # sRGB values (because the source XYZ differs). If auto-adapt
      # wasn't happening, the call would either error out or produce
      # identical wrong results.
      lab_d50 = %Color.Lab{l: 50.0, a: 20.0, b: -10.0, illuminant: :D50}
      lab_d65 = %Color.Lab{l: 50.0, a: 20.0, b: -10.0, illuminant: :D65}

      {:ok, srgb_from_d50} = Color.convert(lab_d50, Color.SRGB)
      {:ok, srgb_from_d65} = Color.convert(lab_d65, Color.SRGB)

      refute_in_delta srgb_from_d50.r, srgb_from_d65.r, 1.0e-4
    end

    test "adapting an XYZ to its own illuminant is an identity" do
      xyz = %Color.XYZ{x: 0.5, y: 0.4, z: 0.3, illuminant: :D65, observer_angle: 2}
      {:ok, out} = Color.XYZ.adapt(xyz, :D65)
      assert out == xyz
    end
  end

  describe "delta_e_2000 Sharma test data" do
    # From Sharma, Wu & Dalal (2005), "The CIEDE2000 Color-Difference
    # Formula: Implementation Notes, Supplementary Test Data, and
    # Mathematical Observations", Table 1.
    @sharma [
      {{50.0, 2.6772, -79.7751}, {50.0, 0.0, -82.7485}, 2.0425},
      {{50.0, 3.1571, -77.2803}, {50.0, 0.0, -82.7485}, 2.8615},
      {{50.0, 2.8361, -74.0200}, {50.0, 0.0, -82.7485}, 3.4412},
      {{50.0, -1.3802, -84.2814}, {50.0, 0.0, -82.7485}, 1.0000},
      {{50.0, -1.1848, -84.8006}, {50.0, 0.0, -82.7485}, 1.0000},
      {{50.0, -0.9009, -85.5211}, {50.0, 0.0, -82.7485}, 1.0000},
      {{50.0, 0.0000, 0.0000}, {50.0, -1.0, 2.0}, 2.3669},
      {{50.0, -1.0, 2.0}, {50.0, 0.0, 0.0}, 2.3669},
      {{50.0, 2.4900, -0.0010}, {50.0, -2.4900, 0.0009}, 7.1792},
      {{50.0, 2.4900, -0.0010}, {50.0, -2.4900, 0.0010}, 7.1792},
      {{50.0, 2.4900, -0.0010}, {50.0, -2.4900, 0.0011}, 7.2195},
      {{50.0, 2.4900, -0.0010}, {50.0, -2.4900, 0.0012}, 7.2195},
      {{50.0, -0.0010, 2.4900}, {50.0, 0.0009, -2.4900}, 4.8045},
      {{50.0, -0.0010, 2.4900}, {50.0, 0.0010, -2.4900}, 4.8045}
    ]

    for {{l1, a1, b1}, {l2, a2, b2}, expected} <- @sharma do
      test "ΔE2000 (#{l1},#{a1},#{b1}) vs (#{l2},#{a2},#{b2}) = #{expected}" do
        lab1 = %Color.Lab{l: unquote(l1), a: unquote(a1), b: unquote(b1)}
        lab2 = %Color.Lab{l: unquote(l2), a: unquote(a2), b: unquote(b2)}
        assert_in_delta Color.Distance.delta_e_2000(lab1, lab2), unquote(expected), 1.0e-4
      end
    end
  end
end
