defmodule Color.Gamut.DiagramTest do
  use ExUnit.Case, async: true

  doctest Color.Gamut.Diagram

  alias Color.Gamut.Diagram

  describe "spectral_locus/2" do
    test "first point is at 380 nm" do
      [first | _] = Diagram.spectral_locus(:xy)
      assert first.wavelength == 380.0
    end

    test "at 520 nm the locus is deep in the green region" do
      points = Diagram.spectral_locus(:xy)
      green = Enum.find(points, &(&1.wavelength == 520.0))

      assert_in_delta green.x, 0.0743, 1.0e-3
      assert_in_delta green.y, 0.8338, 1.0e-3
    end

    test "at 700 nm the locus is at the red corner" do
      points = Diagram.spectral_locus(:xy)
      red = Enum.find(points, &(&1.wavelength == 700.0))

      assert_in_delta red.x, 0.7347, 1.0e-2
      assert_in_delta red.y, 0.2653, 1.0e-2
    end

    test "respects the :step option" do
      step5 = Diagram.spectral_locus(:xy, step: 5)
      step10 = Diagram.spectral_locus(:xy, step: 10)

      assert length(step10) < length(step5)
    end

    test "emits u'v' coordinates when projection is :uv" do
      points = Diagram.spectral_locus(:uv)
      green = Enum.find(points, &(&1.wavelength == 520.0))

      assert Map.has_key?(green, :u)
      assert Map.has_key?(green, :v)
      refute Map.has_key?(green, :x)
    end

    test "CIE 1964 10° observer produces a different locus" do
      two = Diagram.spectral_locus(:xy, observer: 2)
      ten = Diagram.spectral_locus(:xy, observer: 10)

      two_520 = Enum.find(two, &(&1.wavelength == 520.0))
      ten_520 = Enum.find(ten, &(&1.wavelength == 520.0))

      # Both chromaticities are valid (in [0, 1]) and distinct.
      assert two_520.x >= 0.0 and two_520.x <= 1.0
      assert ten_520.x >= 0.0 and ten_520.x <= 1.0
      refute two_520 == ten_520
    end
  end

  describe "triangle/2" do
    test "sRGB primaries match the spec" do
      t = Diagram.triangle(:SRGB)

      assert_in_delta t.red.x, 0.64, 1.0e-4
      assert_in_delta t.red.y, 0.33, 1.0e-4
      assert_in_delta t.green.x, 0.30, 1.0e-4
      assert_in_delta t.green.y, 0.60, 1.0e-4
      assert_in_delta t.blue.x, 0.15, 1.0e-4
      assert_in_delta t.blue.y, 0.06, 1.0e-4
    end

    test "sRGB white is D65" do
      t = Diagram.triangle(:SRGB)
      assert_in_delta t.white.x, 0.3127, 5.0e-3
      assert_in_delta t.white.y, 0.3290, 5.0e-3
    end

    test "Display P3 primaries match the spec" do
      t = Diagram.triangle(:P3_D65)

      assert_in_delta t.red.x, 0.680, 1.0e-3
      assert_in_delta t.red.y, 0.320, 1.0e-3
      assert_in_delta t.green.x, 0.265, 1.0e-3
      assert_in_delta t.green.y, 0.690, 1.0e-3
    end

    test "Rec2020 primaries match the spec" do
      t = Diagram.triangle(:Rec2020)
      assert_in_delta t.red.x, 0.708, 1.0e-3
      assert_in_delta t.green.x, 0.170, 1.0e-3
      assert_in_delta t.blue.x, 0.131, 1.0e-3
    end

    test ":uv projection emits u'v' coordinates" do
      t = Diagram.triangle(:SRGB, :uv)

      for corner <- [:red, :green, :blue, :white] do
        point = Map.fetch!(t, corner)
        assert Map.has_key?(point, :u)
        assert Map.has_key?(point, :v)
      end
    end
  end

  describe "planckian_locus/2" do
    test "returns the expected number of points" do
      assert length(Diagram.planckian_locus(2000..10000//1000)) == 9
    end

    test "6500 K is near the D65 chromaticity" do
      [point] = Diagram.planckian_locus(6500..6500)

      assert_in_delta point.x, 0.3127, 5.0e-3
      assert_in_delta point.y, 0.3290, 5.0e-3
    end

    test "2000 K is orange-warm (high x, mid y)" do
      [warm] = Diagram.planckian_locus(2000..2000)

      assert warm.x > 0.5
      assert warm.y > 0.4
    end

    test ":uv projection" do
      [point] = Diagram.planckian_locus(6500..6500, :uv)
      assert Map.has_key?(point, :u)
      assert Map.has_key?(point, :v)
    end
  end

  describe "chromaticity/2" do
    test "red (#ff0000) maps to sRGB red primary" do
      {:ok, point} = Diagram.chromaticity("#ff0000")
      assert_in_delta point.x, 0.64, 1.0e-2
      assert_in_delta point.y, 0.33, 1.0e-2
    end

    test "white maps near D65" do
      {:ok, point} = Diagram.chromaticity("white")
      assert_in_delta point.x, 0.3127, 5.0e-3
      assert_in_delta point.y, 0.3290, 5.0e-3
    end

    test "propagates errors cleanly" do
      {:error, _} = Diagram.chromaticity("not-a-color")
    end
  end

  describe "xy_to_uv/1 and uv_to_xy/1" do
    test "round-trips through both projections" do
      for _ <- 1..10 do
        x = :rand.uniform() * 0.6
        y = 0.01 + :rand.uniform() * 0.6
        {u, v} = Diagram.xy_to_uv({x, y})
        {x2, y2} = Diagram.uv_to_xy({u, v})

        assert_in_delta x, x2, 1.0e-9
        assert_in_delta y, y2, 1.0e-9
      end
    end

    test "D65 xy maps to D65 u'v'" do
      {u, v} = Diagram.xy_to_uv({0.3127, 0.3290})
      assert_in_delta u, 0.1978, 1.0e-3
      assert_in_delta v, 0.4683, 1.0e-3
    end

    test "zero denominator guards don't crash" do
      # Use explicit +0.0 to satisfy OTP 28's signed-zero pattern
      # match rules; we only care that the guards return zero of
      # either sign rather than dividing by zero.
      assert {+0.0, +0.0} = Diagram.xy_to_uv({0.0, 0.0})
      assert {+0.0, +0.0} = Diagram.uv_to_xy({0.0, 0.0})
    end
  end
end
