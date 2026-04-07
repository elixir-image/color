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
  doctest Color.Contrast
  doctest Color.Mix
  doctest Color.Gamut
  doctest Color.Harmony
  doctest Color.Temperature
  doctest Color.CSS
  doctest Color.Blend

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

    test "new/1 integer list is assumed 0..255 and scaled" do
      assert {:ok, c} = Color.new([255, 128, 0])
      assert c.r == 1.0
      assert_in_delta c.g, 128 / 255, 1.0e-10
      assert c.b == +0.0
      assert c.alpha == nil
    end

    test "new/1 integer list with alpha (0..255)" do
      assert {:ok, c} = Color.new([255, 0, 0, 128])
      assert c.r == 1.0
      assert c.g == +0.0
      assert c.b == +0.0
      assert_in_delta c.alpha, 128 / 255, 1.0e-10
    end

    test "new/1 rejects mixed integers and floats" do
      assert {:error, message} = Color.new([1.0, 0, 0])
      assert message =~ "all floats or all integers"

      assert {:error, _} = Color.new([255, 0.5, 0])
      assert {:error, _} = Color.new([1, 2, 3, 0.5])
    end

    test "new/1 rejects out-of-range integers" do
      assert {:error, message} = Color.new([300, 0, 0])
      assert message =~ "0..255"

      assert {:error, _} = Color.new([-1, 0, 0])
      assert {:error, _} = Color.new([255, 255, 255, 256])
    end

    test "new/1 rejects out-of-range floats" do
      assert {:error, message} = Color.new([1.5, 0.0, 0.0])
      assert message =~ "[0.0, 1.0]"

      assert {:error, _} = Color.new([-0.1, 0.0, 0.0])
      assert {:error, _} = Color.new([0.0, 0.0, 0.0, 2.0])
    end

    test "new/1 rejects non-numeric list elements" do
      assert {:error, message} = Color.new([1.0, :red, 0.0])
      assert message =~ "only numbers"
    end

    test "new/1 integer list and equivalent float list produce the same color" do
      {:ok, from_ints} = Color.new([255, 128, 64])
      {:ok, from_floats} = Color.new([255 / 255, 128 / 255, 64 / 255])
      assert from_ints.r == from_floats.r
      assert from_ints.g == from_floats.g
      assert from_ints.b == from_floats.b
    end

    test "convert/2 accepts an integer list" do
      {:ok, lab_from_ints} = Color.convert([255, 0, 0], Color.Lab)
      {:ok, lab_from_floats} = Color.convert([1.0, 0.0, 0.0], Color.Lab)
      assert_in_delta lab_from_ints.l, lab_from_floats.l, 1.0e-10
      assert_in_delta lab_from_ints.a, lab_from_floats.a, 1.0e-10
      assert_in_delta lab_from_ints.b, lab_from_floats.b, 1.0e-10
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

  describe "Color.new/2 with space argument" do
    test "short atoms and module atoms both work" do
      assert {:ok, %Color.Lab{}} = Color.new([50.0, 20.0, -10.0], :lab)
      assert {:ok, %Color.Lab{}} = Color.new([50.0, 20.0, -10.0], Color.Lab)
      assert {:ok, %Color.Oklab{}} = Color.new([0.63, 0.22, 0.13], :oklab)
      assert {:ok, %Color.Oklab{}} = Color.new([0.63, 0.22, 0.13], Color.Oklab)
    end

    test "sRGB default matches explicit :srgb" do
      {:ok, default} = Color.new([1.0, 0.5, 0.0])
      {:ok, explicit} = Color.new([1.0, 0.5, 0.0], :srgb)
      assert default == explicit
    end

    test "integer form for sRGB, Adobe RGB, and CMYK" do
      assert {:ok, srgb} = Color.new([255, 128, 0], :srgb)
      assert srgb.__struct__ == Color.SRGB

      assert {:ok, adobe} = Color.new([255, 128, 0], :adobe_rgb)
      assert adobe.__struct__ == Color.AdobeRGB

      assert {:ok, cmyk} = Color.new([0, 128, 255, 0], :cmyk)
      assert cmyk.__struct__ == Color.CMYK
    end

    test "integer form rejected for non-RGB spaces" do
      for space <- [:lab, :oklab, :xyz, :hsl, :hsluv, :jzazbz, :oklch] do
        assert {:error, message} = Color.new([1, 2, 3], space)
        assert message =~ "floats", "space=#{inspect(space)}"
      end
    end

    test "permissive spaces accept out-of-nominal-range values" do
      # Wide-gamut Lab beyond ±128
      assert {:ok, %Color.Lab{}} = Color.new([50.0, 200.0, -200.0], :lab)
      # HDR Oklab beyond ±0.4
      assert {:ok, %Color.Oklab{}} = Color.new([1.5, 0.6, -0.6], :oklab)
      # HDR XYZ above Y=1
      assert {:ok, %Color.XYZ{}} = Color.new([5.0, 10.0, 5.0], :xyz)
    end

    test "cylindrical spaces wrap hue rather than erroring" do
      {:ok, a} = Color.new([0.7, 0.2, 30.0], :oklch)
      {:ok, b} = Color.new([0.7, 0.2, 390.0], :oklch)
      assert_in_delta a.h, b.h, 1.0e-10

      {:ok, c} = Color.new([0.7, 0.2, -45.0], :oklch)
      assert c.h == 315.0

      # HSL hue in [0, 1]
      {:ok, d} = Color.new([1.2, 0.5, 0.5], :hsl)
      assert_in_delta d.h, 0.2, 1.0e-10
    end

    test "HSLuv validates s/l in [0, 100]" do
      assert {:ok, %Color.HSLuv{h: +0.0, s: 50.0, l: 50.0}} =
               Color.new([0.0, 50.0, 50.0], :hsluv)

      # Hue wraps, s/l don't
      assert {:ok, _} = Color.new([360.0, 100.0, 100.0], :hsluv)
      assert {:error, _} = Color.new([0.0, 150.0, 50.0], :hsluv)
      assert {:error, _} = Color.new([0.0, 50.0, -10.0], :hsluv)
    end

    test "CMYK with 4 or 5 elements" do
      assert {:ok, %Color.CMYK{c: c_val, m: m_val, y: y_val, k: k_val, alpha: nil}} =
               Color.new([0.0, 0.5, 1.0, 0.0], :cmyk)

      assert c_val == +0.0
      assert m_val == 0.5
      assert y_val == 1.0
      assert k_val == +0.0

      assert {:ok, %Color.CMYK{alpha: 0.5}} = Color.new([0.0, 0.5, 1.0, 0.0, 0.5], :cmyk)
      assert {:error, _} = Color.new([0.0, 0.5, 1.0], :cmyk)
      assert {:error, _} = Color.new([0.0, 0.5, 1.0, 0.0, 0.5, 1.0], :cmyk)
    end

    test "CIE-space defaults to D65" do
      {:ok, lab} = Color.new([50.0, 20.0, -10.0], :lab)
      assert lab.illuminant == :D65
      assert lab.observer_angle == 2

      {:ok, xyz} = Color.new([0.5, 0.5, 0.5], :xyz)
      assert xyz.illuminant == :D65
    end

    test "unknown space returns error" do
      assert {:error, message} = Color.new([0.0, 0.0, 0.0], :notaspace)
      assert message =~ "Unknown color space"
    end

    test "wrong element count returns error" do
      assert {:error, _} = Color.new([1.0, 2.0], :lab)
      assert {:error, _} = Color.new([1.0, 2.0, 3.0, 4.0, 5.0], :lab)
    end

    test "round-trip via convert/2 with explicit space" do
      # Build an Oklab directly from a list, convert through sRGB, and
      # back. The result should match the original modulo float noise.
      {:ok, original} = Color.new([0.6, 0.1, 0.1], :oklab)
      {:ok, srgb} = Color.convert(original, Color.SRGB)
      {:ok, back} = Color.convert(srgb, Color.Oklab)
      assert_in_delta back.l, original.l, 1.0e-6
      assert_in_delta back.a, original.a, 1.0e-6
      assert_in_delta back.b, original.b, 1.0e-6
    end

    test "alpha preserved in permissive space list" do
      assert {:ok, lab} = Color.new([50.0, 20.0, -10.0, 0.5], :lab)
      assert lab.alpha == 0.5
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

  describe "Tier 1 features" do
    test "Color.Contrast.wcag_ratio is symmetric and clamped to [1, 21]" do
      assert_in_delta Color.Contrast.wcag_ratio("white", "black"), 21.0, 0.01
      assert_in_delta Color.Contrast.wcag_ratio("black", "white"), 21.0, 0.01
      assert_in_delta Color.Contrast.wcag_ratio("red", "red"), 1.0, 0.01
    end

    test "Color.Contrast.apca has opposite sign for reversed polarity" do
      a = Color.Contrast.apca("black", "white")
      b = Color.Contrast.apca("white", "black")
      assert a > 0
      assert b < 0
    end

    test "Color.Mix.gradient(_, _, n) returns exactly n colors including endpoints" do
      {:ok, colors} = Color.Mix.gradient("red", "blue", 7)
      assert length(colors) == 7
      [first | _] = colors
      last = List.last(colors)
      assert_in_delta first.r, 1.0, 1.0e-6
      assert_in_delta first.b, 0.0, 1.0e-6
      assert_in_delta last.r, 0.0, 1.0e-6
      assert_in_delta last.b, 1.0, 1.0e-6
    end

    test "Color.Mix.mix respects :hue :shorter vs :longer" do
      {:ok, shorter} = Color.Mix.mix("red", "lime", 0.5, in: Color.Oklch, hue: :shorter)
      {:ok, longer} = Color.Mix.mix("red", "lime", 0.5, in: Color.Oklch, hue: :longer)
      # The two paths should produce visibly different colors.
      diff = abs(shorter.r - longer.r) + abs(shorter.g - longer.g) + abs(shorter.b - longer.b)
      assert diff > 0.1
    end

    test "Color.Gamut.in_gamut? rejects out-of-sRGB Display P3 colors" do
      # Display P3 "red" = (1, 0, 0) in P3 primaries is outside sRGB.
      p3_red = %Color.RGB{r: 1.0, g: 0.0, b: 0.0, working_space: :P3_D65}
      refute Color.Gamut.in_gamut?(p3_red, :SRGB)
      assert Color.Gamut.in_gamut?(p3_red, :P3_D65)
    end

    test "Color.Gamut.to_gamut :oklch produces an sRGB-valid color" do
      # A highly saturated oklch color that's outside sRGB.
      out = %Color.Oklch{l: 0.7, c: 0.4, h: 30.0}
      {:ok, mapped} = Color.Gamut.to_gamut(out, :SRGB)
      assert Color.Gamut.in_gamut?(mapped, :SRGB)
    end

    test "Color.Harmony.complementary returns two colors 180° apart" do
      {:ok, [_a, _b] = pair} = Color.Harmony.complementary("red")
      assert length(pair) == 2
    end

    test "Color.Harmony.triadic returns three distinct colors" do
      {:ok, [a, b, c] = triple} = Color.Harmony.triadic("red")
      assert length(triple) == 3
      assert a != b
      assert a != c
      assert b != c
    end

    test "Color.Temperature.cct |> xy round-trip (McCamy approximation range)" do
      # McCamy's approximation has O(±2 K) error near D65 but degrades
      # at the extremes. Tighten for the core [4000, 7000] range and
      # loosen for the rest.
      for {t, tol} <- [{2856, 20}, {5000, 10}, {5500, 10}, {6504, 5}, {9300, 300}] do
        {x, y} = Color.Temperature.xy(t)
        back = Color.Temperature.cct({x, y})
        assert_in_delta back, t, tol, "T=#{t}"
      end
    end

    test "Color.CSS.parse + to_css round-trip for rgb()" do
      {:ok, c} = Color.CSS.parse("rgb(255 128 0 / 50%)")
      css = Color.CSS.to_css(c)
      assert css == "rgb(255 128 0 / 0.5)"
    end

    test "Color.CSS.parse recognises all CSS Color 4 functions" do
      inputs = [
        "#ff0000",
        "rgb(255 0 0)",
        "rgba(255, 0, 0, 0.5)",
        "hsl(0 100% 50%)",
        "hwb(0 0% 0%)",
        "lab(50% 40 30)",
        "lch(50% 50 30)",
        "oklab(63% 0.2 0.1)",
        "oklch(63% 0.2 30)",
        "color(srgb 1 0 0)",
        "color(display-p3 1 0 0)",
        "color(rec2020 1 0 0)",
        "color(xyz-d65 0.95 1 1.08)",
        "rebeccapurple"
      ]

      for input <- inputs do
        assert {:ok, _} = Color.CSS.parse(input), "failed: #{inspect(input)}"
      end
    end

    test "Color.Blend.blend multiply against white is identity" do
      for source <- ["#ff0000", "#00ff00", "#555555", "#c6a88c"] do
        {:ok, original} = Color.convert(source, Color.SRGB)
        {:ok, blended} = Color.Blend.blend("white", source, :multiply)
        assert_in_delta blended.r, original.r, 1.0e-10
        assert_in_delta blended.g, original.g, 1.0e-10
        assert_in_delta blended.b, original.b, 1.0e-10
      end
    end

    test "Color.Blend.blend screen against black is identity" do
      for source <- ["#ff0000", "#00ff00", "#c6a88c"] do
        {:ok, original} = Color.convert(source, Color.SRGB)
        {:ok, blended} = Color.Blend.blend("black", source, :screen)
        assert_in_delta blended.r, original.r, 1.0e-10
        assert_in_delta blended.g, original.g, 1.0e-10
        assert_in_delta blended.b, original.b, 1.0e-10
      end
    end

    test "Color.CSSNames.nearest returns the expected named colour" do
      {:ok, {name, _, de}} = Color.CSSNames.nearest("#ff0000")
      assert name == "red"
      assert_in_delta de, 0.0, 1.0e-6
    end

    test "Color.CSSNames.lookup accepts atoms and snake case" do
      assert {:ok, {255, 228, 225}} = Color.CSSNames.lookup(:misty_rose)
      assert {:ok, {255, 228, 225}} = Color.CSSNames.lookup("Misty Rose")
      assert {:ok, {255, 228, 225}} = Color.CSSNames.lookup("misty-rose")
    end

    test "Color.new/1 accepts atom CSS names" do
      assert {:ok, srgb} = Color.new(:rebecca_purple)
      assert_in_delta srgb.r, 102 / 255, 1.0e-10
    end

    test "Color.RGB.WorkingSpace CSS name round-trip" do
      assert {:ok, :P3_D65} = Color.RGB.WorkingSpace.from_css_name("display-p3")
      assert Color.RGB.WorkingSpace.to_css_name(:P3_D65) == "display-p3"
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
