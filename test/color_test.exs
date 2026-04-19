defmodule ColorTest do
  use ExUnit.Case

  doctest Color
  doctest Color.Behaviour
  doctest Color.ChromaticAdaptation
  doctest Color.Conversion.Lindbloom
  doctest Color.HSLuv.Gamut
  doctest Color.Spectral.Tables
  doctest Color.Tristimulus
  doctest Color.Lab
  doctest Color.LCHab
  doctest Color.Luv
  doctest Color.LCHuv
  doctest Color.Oklab
  doctest Color.Oklch
  doctest Color.Conversion.Oklab
  doctest Color.XyY
  doctest Color.SRGB
  doctest Color.AdobeRGB
  doctest Color.AppleRGB
  doctest Color.Rec2020
  doctest Color.RGB
  doctest Color.HSL
  doctest Color.HSV
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
  doctest Color.CSS.Names
  doctest Color.ANSI
  doctest Color.Contrast
  doctest Color.Spectral
  doctest Color.Mix
  doctest Color.Gamut
  doctest Color.Harmony
  doctest Color.Temperature
  doctest Color.CSS
  doctest Color.CSS.Tokenizer
  doctest Color.CSS.Calc
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
        assert %Color.HSL{h: 0.5} = ~COLOR[0.5, 1.0, 0.5]h
        assert %Color.HSV{v: 1.0} = ~COLOR[0.5, 1.0, 1.0]v
        assert %Color.CMYK{k: +0.0} = ~COLOR[0.0, 0.5, 1.0, 0.0]k
      end
    end
  end

  describe "any-to-any dispatch" do
    @srgb %Color.SRGB{r: 0.7, g: 0.5, b: 0.3, alpha: 1.0}

    @targets [
      Color.XYZ,
      Color.XyY,
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
      Color.AppleRGB,
      Color.Rec2020,
      Color.HSL,
      Color.HSV
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
      assert {:error, %Color.InvalidComponentError{reason: :mixed_types}} =
               Color.new([1.0, 0, 0])

      assert {:error, %Color.InvalidComponentError{reason: :mixed_types}} =
               Color.new([255, 0.5, 0])

      assert {:error, %Color.InvalidComponentError{reason: :mixed_types}} =
               Color.new([1, 2, 3, 0.5])
    end

    test "new/1 rejects out-of-range integers" do
      assert {:error, %Color.InvalidComponentError{reason: :out_of_range, range: {0, 255}}} =
               Color.new([300, 0, 0])

      assert {:error, %Color.InvalidComponentError{reason: :out_of_range}} =
               Color.new([-1, 0, 0])

      assert {:error, %Color.InvalidComponentError{reason: :out_of_range}} =
               Color.new([255, 255, 255, 256])
    end

    test "new/1 rejects out-of-range floats" do
      assert {:error, %Color.InvalidComponentError{reason: :out_of_range, range: {lo, hi}}} =
               Color.new([1.5, 0.0, 0.0])

      assert lo == +0.0
      assert hi == 1.0

      assert {:error, %Color.InvalidComponentError{reason: :out_of_range}} =
               Color.new([-0.1, 0.0, 0.0])

      assert {:error, %Color.InvalidComponentError{reason: :out_of_range}} =
               Color.new([0.0, 0.0, 0.0, 2.0])
    end

    test "new/1 rejects non-numeric list elements" do
      assert {:error, %Color.InvalidComponentError{reason: :not_numeric}} =
               Color.new([1.0, :red, 0.0])
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

    test "convert/3 accepts working_space: in options keyword (API symmetry)" do
      {:ok, positional} = Color.convert([1.0, 0.5, 0.0], Color.RGB, :Rec2020)

      {:ok, keyword} =
        Color.convert([1.0, 0.5, 0.0], Color.RGB, working_space: :Rec2020)

      assert_in_delta positional.r, keyword.r, 1.0e-10
      assert_in_delta positional.g, keyword.g, 1.0e-10
      assert_in_delta positional.b, keyword.b, 1.0e-10
      assert positional.working_space == :Rec2020
      assert keyword.working_space == :Rec2020
    end

    test "convert_many/2 produces same result as map(convert/2)" do
      colors = ["red", "green", "blue", "white", "black", "#888"]

      {:ok, batch} = Color.convert_many(colors, Color.Lab)

      individually =
        Enum.map(colors, fn c ->
          {:ok, lab} = Color.convert(c, Color.Lab)
          lab
        end)

      assert batch == individually
    end

    test "convert_many/3 with positional working_space" do
      {:ok, list} = Color.convert_many([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], Color.RGB, :Rec2020)
      assert length(list) == 2
      assert Enum.all?(list, &match?(%Color.RGB{working_space: :Rec2020}, &1))
    end

    test "convert_many/3 with working_space: in options" do
      {:ok, list} =
        Color.convert_many([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], Color.RGB, working_space: :Rec2020)

      assert length(list) == 2
    end

    test "convert_many/4 supports rendering intents" do
      p3_red = %Color.RGB{r: 1.0, g: 0.0, b: 0.0, working_space: :P3_D65}

      {:ok, [mapped]} =
        Color.convert_many([p3_red], Color.RGB, :SRGB, intent: :perceptual)

      assert mapped.r <= 1.0 + 1.0e-5
    end

    test "convert_many/2 halts on first error" do
      assert {:error, %Color.UnknownColorNameError{}} =
               Color.convert_many(["red", "notacolor", "blue"], Color.Lab)
    end

    test "convert_many/2 returns Color.MissingWorkingSpaceError for Color.RGB without working_space" do
      assert {:error, %Color.MissingWorkingSpaceError{}} =
               Color.convert_many(["red"], Color.RGB)
    end

    test "convert_many/2 accepts an empty list" do
      assert {:ok, []} = Color.convert_many([], Color.Lab)
    end

    test "convert/3 keyword form composes with rendering intent" do
      p3_red = %Color.RGB{r: 1.0, g: 0.0, b: 0.0, working_space: :P3_D65}

      {:ok, mapped} =
        Color.convert(p3_red, Color.RGB,
          working_space: :SRGB,
          intent: :perceptual
        )

      assert mapped.r <= 1.0 + 1.0e-5
      assert mapped.r >= 0.0
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
        assert {:error, %Color.InvalidComponentError{reason: :integers_not_allowed}} =
                 Color.new([1, 2, 3], space),
               "space=#{inspect(space)}"
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
      assert {:error, %Color.UnknownColorSpaceError{space: :notaspace}} =
               Color.new([0.0, 0.0, 0.0], :notaspace)
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
      Color.XyY,
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
      Color.AppleRGB,
      Color.Rec2020,
      Color.HSL,
      Color.HSV
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

  describe "Color.ANSI" do
    test "to_string/2 truecolor foreground" do
      assert Color.ANSI.to_string("red") == "\e[38;2;255;0;0m"
      assert Color.ANSI.to_string("#00ff00") == "\e[38;2;0;255;0m"
      assert Color.ANSI.to_string([0, 0, 255]) == "\e[38;2;0;0;255m"
    end

    test "to_string/2 truecolor background" do
      assert Color.ANSI.to_string("red", layer: :background) == "\e[48;2;255;0;0m"
    end

    test "to_string/2 ansi256" do
      assert Color.ANSI.to_string("red", mode: :ansi256) == "\e[38;5;196m"
      assert Color.ANSI.to_string("black", mode: :ansi256) == "\e[38;5;0m"
      # Pure white is an exact match for both palette index 15 (bright
      # white) and 231 (cube corner). Either is acceptable — the
      # encoder picks whichever comes first.
      assert Color.ANSI.to_string("white", mode: :ansi256) in [
               "\e[38;5;15m",
               "\e[38;5;231m"
             ]

      # Background form
      assert Color.ANSI.to_string("red", mode: :ansi256, layer: :background) ==
               "\e[48;5;196m"
    end

    test "to_string/2 ansi16" do
      # Pure red maps to bright red (index 9) rather than dim red (1)
      # because (255, 0, 0) is perceptually closer to (255, 85, 85)
      # than to (170, 0, 0).
      assert Color.ANSI.to_string("red", mode: :ansi16) == "\e[91m"

      # Background form uses 101 rather than 91
      assert Color.ANSI.to_string("red", mode: :ansi16, layer: :background) ==
               "\e[101m"

      # Dim red matches the standard palette
      dim = %Color.SRGB{r: 170 / 255, g: 0.0, b: 0.0}
      assert Color.ANSI.to_string(dim, mode: :ansi16) == "\e[31m"
    end

    test "to_string/2 converts non-sRGB inputs" do
      lab_red = %Color.Lab{l: 53.2408, a: 80.0925, b: 67.2032}
      assert Color.ANSI.to_string(lab_red) == "\e[38;2;255;0;0m"
    end

    test "to_string/2 raises on unknown mode" do
      assert_raise ArgumentError, ~r/Unknown Color.ANSI mode/, fn ->
        Color.ANSI.to_string("red", mode: :nonsense)
      end
    end

    test "parse/1 16-colour foreground" do
      assert {:ok, %Color.SRGB{} = c, :foreground} = Color.ANSI.parse("\e[31m")
      assert Color.to_hex(c) == "#aa0000"
    end

    test "parse/1 16-colour background" do
      assert {:ok, _c, :background} = Color.ANSI.parse("\e[41m")
    end

    test "parse/1 bright 16-colour" do
      assert {:ok, c, :foreground} = Color.ANSI.parse("\e[91m")
      assert Color.to_hex(c) == "#ff5555"

      assert {:ok, _, :background} = Color.ANSI.parse("\e[101m")
    end

    test "parse/1 256-colour" do
      assert {:ok, c, :foreground} = Color.ANSI.parse("\e[38;5;196m")
      assert Color.to_hex(c) == "#ff0000"

      assert {:ok, c, :background} = Color.ANSI.parse("\e[48;5;21m")
      # Cube index 21 = (0, 0, 255)
      assert Color.to_hex(c) == "#0000ff"
    end

    test "parse/1 truecolor" do
      assert {:ok, c, :foreground} = Color.ANSI.parse("\e[38;2;123;45;67m")
      assert Color.to_hex(c) == "#7b2d43"
    end

    test "parse/1 ignores style parameters before the colour" do
      assert {:ok, c, :foreground} = Color.ANSI.parse("\e[1;31m")
      assert Color.to_hex(c) == "#aa0000"
    end

    test "parse/1 ignores style parameters after the colour" do
      assert {:ok, c, :foreground} = Color.ANSI.parse("\e[31;1m")
      assert Color.to_hex(c) == "#aa0000"
    end

    test "parse/1 returns an error on the reset sequence" do
      assert {:error, %Color.ANSI.ParseError{reason: :no_colour_param}} =
               Color.ANSI.parse("\e[0m")
    end

    test "parse/1 returns an error on a bold-only sequence" do
      assert {:error, %Color.ANSI.ParseError{reason: :no_colour_param}} =
               Color.ANSI.parse("\e[1m")
    end

    test "parse/1 returns an error when the sequence is missing the CSI" do
      assert {:error, %Color.ANSI.ParseError{reason: :no_csi}} =
               Color.ANSI.parse("31m")
    end

    test "parse/1 returns an error when the sequence is missing the terminator" do
      assert {:error, %Color.ANSI.ParseError{reason: :no_terminator}} =
               Color.ANSI.parse("\e[31")
    end

    test "parse/1 returns an error on an out-of-range 256-colour index" do
      assert {:error, %Color.ANSI.ParseError{reason: :bad_index}} =
               Color.ANSI.parse("\e[38;5;999m")
    end

    test "parse/1 returns an error on out-of-range truecolor bytes" do
      assert {:error, %Color.ANSI.ParseError{reason: :bad_rgb}} =
               Color.ANSI.parse("\e[38;2;300;0;0m")
    end

    test "to_string/2 |> parse/1 round-trip (truecolor)" do
      for hex <- ["#ff0000", "#00ff00", "#0000ff", "#abcdef", "#123456"] do
        encoded = Color.ANSI.to_string(hex)
        assert {:ok, srgb, :foreground} = Color.ANSI.parse(encoded)
        assert Color.to_hex(srgb) == hex
      end
    end

    test "wrap/3 wraps text in colour + reset" do
      assert Color.ANSI.wrap("hello", "red") ==
               "\e[38;2;255;0;0mhello\e[0m"

      assert Color.ANSI.wrap("hi", "red", mode: :ansi16) ==
               "\e[91mhi\e[0m"
    end

    test "nearest_256 and nearest_16 return sane values" do
      assert Color.ANSI.nearest_256("#ff0000") == 196
      assert Color.ANSI.nearest_256("#000000") == 0
      # Pure white is an exact match for both 15 (bright white) and
      # 231 (cube corner).
      assert Color.ANSI.nearest_256("#ffffff") in [15, 231]
      assert Color.ANSI.nearest_256([128, 128, 128]) in 240..248

      assert Color.ANSI.nearest_16("#000000") == 0
      assert Color.ANSI.nearest_16("#ffffff") == 15
    end

    test "palette_256/0 and palette_16/0 return the expected data" do
      assert length(Color.ANSI.palette_256()) == 256
      assert length(Color.ANSI.palette_16()) == 16

      # Cube index 21 = (0, 0, 255)
      assert Enum.find(Color.ANSI.palette_256(), &match?({21, _}, &1)) ==
               {21, {0, 0, 255}}

      # Last grayscale entry is index 255 = (238, 238, 238)
      assert Enum.find(Color.ANSI.palette_256(), &match?({255, _}, &1)) ==
               {255, {238, 238, 238}}
    end
  end

  describe "Color.to_hex/1 and Color.to_css/1,2" do
    test "to_hex accepts any input form" do
      assert Color.to_hex("#ff0000") == "#ff0000"
      assert Color.to_hex("red") == "#ff0000"
      assert Color.to_hex(:rebecca_purple) == "#663399"
      assert Color.to_hex([1.0, 0.0, 0.0]) == "#ff0000"
      assert Color.to_hex([255, 128, 0]) == "#ff8000"
      assert Color.to_hex(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0}) == "#ff0000"
    end

    test "to_hex converts non-sRGB colours through sRGB first" do
      # Lab red ≈ sRGB red
      lab = %Color.Lab{l: 53.2408, a: 80.0925, b: 67.2032}
      assert Color.to_hex(lab) == "#ff0000"
    end

    test "to_hex emits #rrggbbaa for translucent alpha" do
      assert Color.to_hex(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0, alpha: 0.5}) ==
               "#ff000080"
    end

    test "to_hex raises a typed exception on invalid input" do
      assert_raise Color.InvalidComponentError, fn ->
        Color.to_hex([1.5, 0.0, 0.0])
      end

      assert_raise Color.UnknownColorNameError, fn ->
        Color.to_hex("notacolor")
      end
    end

    test "to_css returns the canonical per-struct form" do
      assert Color.to_css(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0}) == "rgb(255 0 0)"
      assert Color.to_css(%Color.Lab{l: 50.0, a: 40.0, b: 30.0}) == "lab(50% 40 30)"
      assert Color.to_css(%Color.Oklch{l: 0.7, c: 0.15, h: 180.0}) == "oklch(70% 0.15 180)"
    end

    test "to_css accepts string + atom + list inputs via new/1" do
      assert Color.to_css("#ff0000") == "rgb(255 0 0)"
      assert Color.to_css("rebeccapurple") == "rgb(102 51 153)"
      assert Color.to_css(:red) == "rgb(255 0 0)"
      assert Color.to_css([1.0, 0.5, 0.0]) == "rgb(255 128 0)"
      assert Color.to_css([255, 0, 0]) == "rgb(255 0 0)"
    end

    test "to_css preserves alpha" do
      assert Color.to_css(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0, alpha: 0.5}) ==
               "rgb(255 0 0 / 0.5)"
    end

    test "to_css honours the :as option for sRGB" do
      red = %Color.SRGB{r: 1.0, g: 0.0, b: 0.0}
      assert Color.to_css(red, as: :hex) == "#ff0000"
      assert Color.to_css(red, as: :rgb) == "rgb(255 0 0)"
      assert Color.to_css(red, as: :color) == "color(srgb 1 0 0)"
    end

    test "to_css raises a typed exception on invalid input" do
      assert_raise Color.InvalidComponentError, fn ->
        Color.to_css([300, 0, 0])
      end
    end

    test "to_ansi delegates to Color.ANSI.to_string" do
      assert Color.to_ansi("red") == Color.ANSI.to_string("red")
      assert Color.to_ansi("red", mode: :ansi256) == "\e[38;5;196m"
      assert Color.to_ansi("red", mode: :ansi16) == "\e[91m"
      assert Color.to_ansi("red", layer: :background) == "\e[48;2;255;0;0m"

      # Accepts non-sRGB input via new/1
      lab_red = %Color.Lab{l: 53.2408, a: 80.0925, b: 67.2032}
      assert Color.to_ansi(lab_red) == "\e[38;2;255;0;0m"
    end

    test "to_ansi raises a typed exception on invalid input" do
      assert_raise Color.InvalidComponentError, fn ->
        Color.to_ansi([1.5, 0.0, 0.0])
      end
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

    test "Color.CSS.Names.nearest returns the expected named colour" do
      {:ok, {name, _, de}} = Color.CSS.Names.nearest("#ff0000")
      assert name == "red"
      assert_in_delta de, 0.0, 1.0e-6
    end

    test "Color.CSS.Names.lookup accepts atoms and snake case" do
      assert {:ok, {255, 228, 225}} = Color.CSS.Names.lookup(:misty_rose)
      assert {:ok, {255, 228, 225}} = Color.CSS.Names.lookup("Misty Rose")
      assert {:ok, {255, 228, 225}} = Color.CSS.Names.lookup("misty-rose")
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

  describe "Tier 2 features" do
    test "Color.luminance/1 delegates to Color.Contrast.relative_luminance/1" do
      assert Color.luminance("white") == 1.0
      assert Color.luminance("black") == 0.0
      assert_in_delta Color.luminance("red"), 0.2126, 1.0e-4
    end

    test "Color.sort/2 by luminance" do
      {:ok, sorted} = Color.sort(["white", "black", "#888"], by: :luminance)
      assert Enum.map(sorted, &Color.SRGB.to_hex/1) == ["#000000", "#888888", "#ffffff"]
    end

    test "Color.sort/2 order: :desc reverses the order" do
      {:ok, sorted} = Color.sort(["white", "black", "#888"], by: :luminance, order: :desc)
      assert_in_delta List.first(sorted).r, 1.0, 1.0e-10
    end

    test "Color.sort/2 by lightness uses Lab L*" do
      {:ok, sorted} = Color.sort(["red", "green", "blue"], by: :lightness)

      lightnesses =
        Enum.map(sorted, fn c ->
          {:ok, lab} = Color.convert(c, Color.Lab)
          lab.l
        end)

      assert lightnesses == Enum.sort(lightnesses)
    end

    test "Color.sort/2 with custom function" do
      # Sort by blue channel descending.
      {:ok, sorted} = Color.sort(["red", "blue", "green"], by: fn c -> -c.b end)
      assert_in_delta List.first(sorted).b, 1.0, 1.0e-10
    end

    test "Color.sort/2 errors on unknown :by preset" do
      assert_raise Color.UnknownSortKeyError, ~r/Unknown sort key/, fn ->
        Color.sort(["red"], by: :nonsense)
      end
    end

    test "rendering intent :absolute_colorimetric bypasses chromatic adaptation" do
      # Lab tagged D50 vs D65 should give different sRGB with the
      # default :relative_colorimetric intent but identical sRGB with
      # :absolute_colorimetric (because the XYZ values are the same,
      # just differently-interpreted).
      lab = %Color.Lab{l: 50.0, a: 20.0, b: -10.0, illuminant: :D50}

      {:ok, rel} = Color.convert(lab, Color.SRGB)
      {:ok, abs} = Color.convert(lab, Color.SRGB, intent: :absolute_colorimetric)

      # They should differ because one adapts D50 → D65 and the other doesn't.
      refute_in_delta rel.r, abs.r, 1.0e-4
    end

    test "rendering intent :perceptual gamut-maps Display P3 into sRGB" do
      p3_red = %Color.RGB{r: 1.0, g: 0.0, b: 0.0, working_space: :P3_D65}

      {:ok, mapped} = Color.convert(p3_red, Color.SRGB, intent: :perceptual)
      assert Color.Gamut.in_gamut?(mapped, :SRGB)

      # Without the intent, the sRGB result is out-of-gamut (r > 1).
      {:ok, clipped_linear} = Color.convert(p3_red, Color.RGB, :SRGB)
      refute clipped_linear.r <= 1.0 + 1.0e-5
    end

    test "rendering intent :perceptual into Color.RGB works" do
      p3_red = %Color.RGB{r: 1.0, g: 0.0, b: 0.0, working_space: :P3_D65}

      {:ok, mapped} = Color.convert(p3_red, Color.RGB, :SRGB, intent: :perceptual)
      assert mapped.r <= 1.0 + 1.0e-5
      assert mapped.g >= -1.0e-5
      assert mapped.b >= -1.0e-5
    end

    test "Color.XYZ.apply_bpc/3 is identity when black points match" do
      xyz = %Color.XYZ{x: 0.5, y: 0.4, z: 0.3, illuminant: :D65}
      assert Color.XYZ.apply_bpc(xyz, 0.0, 0.0) == xyz
      assert Color.XYZ.apply_bpc(xyz, 0.05, 0.05) == xyz
    end

    test "Color.XYZ.apply_bpc/3 maps source black to dest black" do
      source_black = %Color.XYZ{x: 0.05, y: 0.05, z: 0.05, illuminant: :D65}
      out = Color.XYZ.apply_bpc(source_black, 0.05, 0.0)
      assert_in_delta out.x, 0.0, 1.0e-12
      assert_in_delta out.y, 0.0, 1.0e-12
      assert_in_delta out.z, 0.0, 1.0e-12
    end

    test "Color.XYZ.apply_bpc/3 keeps the source white fixed" do
      white = %Color.XYZ{x: 1.0, y: 1.0, z: 1.0, illuminant: :D65}
      out = Color.XYZ.apply_bpc(white, 0.05, 0.0)
      assert_in_delta out.x, 1.0, 1.0e-12
      assert_in_delta out.y, 1.0, 1.0e-12
      assert_in_delta out.z, 1.0, 1.0e-12
    end

    test "Color.Spectral emissive SPD → XYZ for every built-in illuminant" do
      expected = %{
        D65: {0.9504, 1.0, 1.0888},
        D50: {0.9642, 1.0, 0.8251},
        A: {1.0985, 1.0, 0.3558},
        E: {1.0, 1.0, 1.0}
      }

      for {name, {ex, ey, ez}} <- expected do
        spd = Color.Spectral.illuminant(name)
        {:ok, xyz} = Color.Spectral.to_xyz(spd, illuminant: name)
        assert_in_delta xyz.x, ex, 1.0e-3, "#{name} x"
        assert_in_delta xyz.y, ey, 1.0e-3, "#{name} y"
        assert_in_delta xyz.z, ez, 1.0e-3, "#{name} z"
      end
    end

    test "Color.Spectral perfect diffuser matches the illuminant's white point" do
      perfect = %Color.Spectral{
        wavelengths: Color.Spectral.Tables.wavelengths(),
        values: List.duplicate(1.0, 81)
      }

      {:ok, d65} = Color.Spectral.reflectance_to_xyz(perfect, :D65)
      assert_in_delta d65.x, 0.9504, 1.0e-3
      assert_in_delta d65.z, 1.0888, 1.0e-3

      {:ok, d50} = Color.Spectral.reflectance_to_xyz(perfect, :D50)
      assert_in_delta d50.x, 0.9642, 1.0e-3
      assert_in_delta d50.z, 0.8251, 1.0e-3
    end

    test "Color.Spectral 10° observer differs from 2° observer" do
      perfect = %Color.Spectral{
        wavelengths: Color.Spectral.Tables.wavelengths(),
        values: List.duplicate(1.0, 81)
      }

      {:ok, xyz2} = Color.Spectral.reflectance_to_xyz(perfect, :D65, observer: 2)
      {:ok, xyz10} = Color.Spectral.reflectance_to_xyz(perfect, :D65, observer: 10)

      # The 10° observer gives different chromaticity because the
      # CMFs are different.
      refute_in_delta xyz2.x, xyz10.x, 1.0e-5
    end

    test "Color.Spectral.metamerism/4 is zero for identical samples" do
      sample = %Color.Spectral{
        wavelengths: Color.Spectral.Tables.wavelengths(),
        values: List.duplicate(0.5, 81)
      }

      {:ok, de} = Color.Spectral.metamerism(sample, sample, :D65, :A)
      assert de == 0.0
    end

    test "Color.Spectral linear resample onto sparser grid" do
      # A sparse 50 nm-spaced source, resampled onto the 5 nm grid.
      sparse = %Color.Spectral{
        wavelengths: [400.0, 500.0, 600.0, 700.0],
        values: [0.0, 1.0, 1.0, 0.0]
      }

      resampled =
        Color.Spectral.resample(sparse, [400.0, 450.0, 500.0, 550.0, 600.0, 650.0, 700.0])

      assert Enum.at(resampled, 0) == 0.0
      assert Enum.at(resampled, 1) == 0.5
      assert Enum.at(resampled, 2) == 1.0
      assert Enum.at(resampled, 4) == 1.0
      assert Enum.at(resampled, 6) == 0.0
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
