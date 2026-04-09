defmodule Color.PropertyTest do
  @moduledoc """
  Property-based tests for the conversion pipeline. The general
  pattern is: generate a random sRGB color, convert it through some
  derived space, convert back, and assert the result is within a
  per-space tolerance of the original.

  Some spaces (Oklab, Oklch, JzAzBz, IPT, CAM16-UCS, ICtCp, YCbCr,
  HSLuv, HPLuv) have published matrices rounded to ~10 significant
  digits, which limits round-trip precision. The tolerances below
  are calibrated against the existing point-test deltas.

  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  # ----------------------------------------------------------------------
  # Generators
  # ----------------------------------------------------------------------

  defp unit, do: float(min: 0.0, max: 1.0)
  defp degree, do: float(min: 0.0, max: 360.0)

  defp srgb_color do
    gen all(r <- unit(), g <- unit(), b <- unit()) do
      %Color.SRGB{r: r, g: g, b: b}
    end
  end

  defp srgb_color_with_alpha do
    gen all(r <- unit(), g <- unit(), b <- unit(), a <- unit()) do
      %Color.SRGB{r: r, g: g, b: b, alpha: a}
    end
  end

  # ----------------------------------------------------------------------
  # Round-trip identity
  # ----------------------------------------------------------------------

  describe "round-trip identity" do
    @round_trip_targets [
      {Color.XYZ, 1.0e-12},
      {Color.XyY, 1.0e-12},
      {Color.Lab, 1.0e-10},
      {Color.LCHab, 1.0e-10},
      {Color.Luv, 1.0e-10},
      {Color.LCHuv, 1.0e-10},
      {Color.Oklab, 1.0e-5},
      {Color.Oklch, 1.0e-5},
      {Color.HSLuv, 1.0e-4},
      {Color.HPLuv, 1.0e-4},
      {Color.IPT, 1.0e-5},
      {Color.JzAzBz, 1.0e-4},
      {Color.ICtCp, 1.0e-4},
      {Color.YCbCr, 1.0e-12},
      {Color.CAM16UCS, 1.0e-3},
      {Color.HSL, 1.0e-12},
      {Color.HSV, 1.0e-12},
      {Color.CMYK, 1.0e-12},
      {Color.SRGB, 1.0e-12},
      {Color.AdobeRGB, 1.0e-10}
    ]

    for {target, tolerance} <- @round_trip_targets do
      property "round-trips sRGB through #{inspect(target)} within #{tolerance}" do
        check all(color <- srgb_color()) do
          {:ok, converted} = Color.convert(color, unquote(target))
          {:ok, back} = Color.convert(converted, Color.SRGB)

          assert_in_delta back.r, color.r, unquote(tolerance)
          assert_in_delta back.g, color.g, unquote(tolerance)
          assert_in_delta back.b, color.b, unquote(tolerance)
        end
      end
    end
  end

  # ----------------------------------------------------------------------
  # Alpha preservation
  # ----------------------------------------------------------------------

  describe "alpha preservation" do
    @alpha_targets [
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
      Color.IPT,
      Color.JzAzBz,
      Color.ICtCp,
      Color.YCbCr,
      Color.CAM16UCS,
      Color.HSL,
      Color.HSV,
      Color.CMYK,
      Color.AdobeRGB
    ]

    for target <- @alpha_targets do
      property "alpha is preserved through #{inspect(target)}" do
        check all(color <- srgb_color_with_alpha()) do
          {:ok, converted} = Color.convert(color, unquote(target))
          assert converted.alpha == color.alpha
        end
      end
    end
  end

  # ----------------------------------------------------------------------
  # Cylindrical hue wrap-around
  # ----------------------------------------------------------------------

  describe "hue wrap-around" do
    property "Oklch normalises h + 360 to h" do
      check all(
              l <- float(min: 0.05, max: 0.95),
              c <- float(min: 0.0, max: 0.3),
              h <- degree()
            ) do
        {:ok, a} = Color.new([l, c, h], :oklch)
        {:ok, b} = Color.new([l, c, h + 360.0], :oklch)
        assert_in_delta a.h, b.h, 1.0e-10
      end
    end

    property "LCHab normalises negative hue" do
      check all(
              l <- float(min: 0.0, max: 100.0),
              c <- float(min: 0.0, max: 100.0),
              h <- degree()
            ) do
        {:ok, a} = Color.new([l, c, h], :lch)
        {:ok, b} = Color.new([l, c, h - 360.0], :lch)
        assert_in_delta a.h, b.h, 1.0e-10
      end
    end
  end

  # ----------------------------------------------------------------------
  # Gamut mapping invariant
  # ----------------------------------------------------------------------

  describe "gamut mapping" do
    property "to_gamut(:SRGB) always lands inside the sRGB gamut" do
      # Generate Oklch values that may or may not be inside sRGB.
      check all(
              l <- float(min: 0.05, max: 0.98),
              c <- float(min: 0.0, max: 0.5),
              h <- degree()
            ) do
        oklch = %Color.Oklch{l: l, c: c, h: h}
        {:ok, mapped} = Color.Gamut.to_gamut(oklch, :SRGB)
        assert Color.Gamut.in_gamut?(mapped, :SRGB)
      end
    end

    property "to_gamut(:P3_D65) always lands inside the P3 gamut" do
      check all(
              l <- float(min: 0.05, max: 0.98),
              c <- float(min: 0.0, max: 0.5),
              h <- degree()
            ) do
        oklch = %Color.Oklch{l: l, c: c, h: h}
        {:ok, mapped} = Color.Gamut.to_gamut(oklch, :P3_D65)
        assert Color.Gamut.in_gamut?(mapped, :P3_D65)
      end
    end
  end

  # ----------------------------------------------------------------------
  # Color difference symmetry
  # ----------------------------------------------------------------------

  describe "delta_e symmetry" do
    property "delta_e_2000 is symmetric" do
      check all(
              c1 <- srgb_color(),
              c2 <- srgb_color()
            ) do
        a = Color.Distance.delta_e_2000(c1, c2)
        b = Color.Distance.delta_e_2000(c2, c1)
        assert_in_delta a, b, 1.0e-10
      end
    end

    property "delta_e_2000(c, c) is zero" do
      check all(c <- srgb_color()) do
        assert Color.Distance.delta_e_2000(c, c) == +0.0
      end
    end

    property "delta_e_76 is symmetric and zero on identity" do
      check all(
              c1 <- srgb_color(),
              c2 <- srgb_color()
            ) do
        assert Color.Distance.delta_e_76(c1, c2) ==
                 Color.Distance.delta_e_76(c2, c1)
      end

      check all(c <- srgb_color()) do
        assert Color.Distance.delta_e_76(c, c) == +0.0
      end
    end
  end

  # ----------------------------------------------------------------------
  # Mix endpoint identity
  # ----------------------------------------------------------------------

  describe "mix endpoints" do
    @mix_spaces [Color.SRGB, Color.Lab, Color.Oklab, Color.Oklch, Color.LCHab]

    for space <- @mix_spaces do
      property "mix(a, b, 0.0) ≈ a in #{inspect(space)}" do
        check all(
                c1 <- srgb_color(),
                c2 <- srgb_color()
              ) do
          {:ok, mixed} = Color.Mix.mix(c1, c2, 0.0, in: unquote(space))
          assert_in_delta mixed.r, c1.r, 1.0e-5
          assert_in_delta mixed.g, c1.g, 1.0e-5
          assert_in_delta mixed.b, c1.b, 1.0e-5
        end
      end

      property "mix(a, b, 1.0) ≈ b in #{inspect(space)}" do
        check all(
                c1 <- srgb_color(),
                c2 <- srgb_color()
              ) do
          {:ok, mixed} = Color.Mix.mix(c1, c2, 1.0, in: unquote(space))
          assert_in_delta mixed.r, c2.r, 1.0e-5
          assert_in_delta mixed.g, c2.g, 1.0e-5
          assert_in_delta mixed.b, c2.b, 1.0e-5
        end
      end
    end
  end

  # ----------------------------------------------------------------------
  # WCAG contrast ratio bounds
  # ----------------------------------------------------------------------

  describe "WCAG contrast ratio bounds" do
    property "is always in [1.0, 21.0]" do
      check all(
              c1 <- srgb_color(),
              c2 <- srgb_color()
            ) do
        ratio = Color.Contrast.wcag_ratio(c1, c2)
        assert ratio >= 1.0
        assert ratio <= 21.0 + 1.0e-9
      end
    end

    property "is symmetric" do
      check all(
              c1 <- srgb_color(),
              c2 <- srgb_color()
            ) do
        a = Color.Contrast.wcag_ratio(c1, c2)
        b = Color.Contrast.wcag_ratio(c2, c1)
        assert_in_delta a, b, 1.0e-12
      end
    end
  end
end
