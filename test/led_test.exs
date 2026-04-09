defmodule Color.LEDTest do
  use ExUnit.Case, async: true

  doctest Color.LED
  doctest Color.LED.RGBW
  doctest Color.LED.RGBWW

  alias Color.LED

  describe "chip_options/1" do
    test "returns RGBW options for WS2814 warm white" do
      assert LED.chip_options(:ws2814_ww) == [kind: :rgbw, white_temperature: 3000]
    end

    test "returns RGBWW options for WS2805" do
      assert LED.chip_options(:ws2805) ==
               [kind: :rgbww, warm_temperature: 3000, cool_temperature: 6500]
    end

    test "every supported chip has a :kind" do
      for chip <- LED.chips() do
        opts = LED.chip_options(chip)
        assert Keyword.get(opts, :kind) in [:rgbw, :rgbww]
      end
    end
  end

  describe "RGBW.from_srgb/2" do
    test "white input drives the white LED to full and RGB to zero" do
      {:ok, white} = Color.new("#ffffff")
      pixel = LED.RGBW.from_srgb(white, white_temperature: 6500)

      assert_in_delta pixel.w, 1.0, 1.0e-2
      assert_in_delta pixel.r, 0.0, 5.0e-2
      assert_in_delta pixel.g, 0.0, 5.0e-2
      assert_in_delta pixel.b, 0.0, 5.0e-2
    end

    test "black input leaves every channel at zero" do
      {:ok, black} = Color.new("#000000")
      pixel = LED.RGBW.from_srgb(black, white_temperature: 4500)

      assert pixel.w == 0.0
      assert pixel.r == 0.0
      assert pixel.g == 0.0
      assert pixel.b == 0.0
    end

    test "pure saturated red keeps white off" do
      {:ok, red} = Color.new("#ff0000")
      pixel = LED.RGBW.from_srgb(red, white_temperature: 4500)

      assert pixel.w == 0.0
      assert_in_delta pixel.r, 1.0, 1.0e-6
    end

    test "accepts a chip atom" do
      {:ok, orange} = Color.new("#ffa500")
      pixel = LED.RGBW.from_srgb(orange, chip: :ws2814_nw)

      assert pixel.white_temperature == 4500
    end

    test "rejects RGBWW chip" do
      {:ok, orange} = Color.new("#ffa500")

      assert_raise ArgumentError, fn ->
        LED.RGBW.from_srgb(orange, chip: :ws2805)
      end
    end

    test "preserves alpha" do
      {:ok, srgb} = Color.new([1.0, 0.5, 0.2, 0.5])
      pixel = LED.RGBW.from_srgb(srgb, white_temperature: 3000)
      assert pixel.alpha == 0.5
    end
  end

  describe "RGBW.to_srgb/1" do
    test "round-trips an achromatic colour close to identity" do
      {:ok, grey} = Color.new("#808080")
      pixel = LED.RGBW.from_srgb(grey, white_temperature: 6500)
      {:ok, back} = LED.RGBW.to_srgb(pixel)

      assert_in_delta back.r, grey.r, 5.0e-3
      assert_in_delta back.g, grey.g, 5.0e-3
      assert_in_delta back.b, grey.b, 5.0e-3
    end

    test "round-trips saturated red exactly" do
      {:ok, red} = Color.new("#ff0000")
      pixel = LED.RGBW.from_srgb(red, white_temperature: 4500)
      {:ok, back} = LED.RGBW.to_srgb(pixel)

      assert_in_delta back.r, 1.0, 1.0e-6
      assert_in_delta back.g, 0.0, 1.0e-6
      assert_in_delta back.b, 0.0, 1.0e-6
    end
  end

  describe "RGBW.to_xyz/1" do
    test "returns a Color.XYZ struct" do
      {:ok, srgb} = Color.new("#336699")
      pixel = LED.RGBW.from_srgb(srgb, white_temperature: 3000)

      assert {:ok, %Color.XYZ{}} = LED.RGBW.to_xyz(pixel)
    end
  end

  describe "RGBWW.from_srgb/2" do
    test "white input activates white LEDs and leaves RGB near zero" do
      {:ok, white} = Color.new("#ffffff")
      pixel = LED.RGBWW.from_srgb(white, chip: :ws2805)

      assert pixel.ww + pixel.cw > 0.9
      assert_in_delta pixel.r, 0.0, 5.0e-2
      assert_in_delta pixel.g, 0.0, 5.0e-2
      assert_in_delta pixel.b, 0.0, 5.0e-2
    end

    test "warm target biases towards the warm white LED" do
      {:ok, warm_white} = Color.new([1.0, 0.85, 0.6])
      pixel = LED.RGBWW.from_srgb(warm_white, chip: :ws2805)

      assert pixel.ww > pixel.cw
    end

    test "cool target biases towards the cool white LED" do
      {:ok, cool_white} = Color.new([0.85, 0.9, 1.0])
      pixel = LED.RGBWW.from_srgb(cool_white, chip: :ws2805)

      assert pixel.cw > pixel.ww
    end

    test "rejects RGBW chip" do
      {:ok, orange} = Color.new("#ffa500")

      assert_raise ArgumentError, fn ->
        LED.RGBWW.from_srgb(orange, chip: :ws2814_ww)
      end
    end

    test "accepts chip_options/1 list directly" do
      {:ok, target} = Color.new("#ffa500")
      options = LED.chip_options(:ws2805)
      pixel = LED.RGBWW.from_srgb(target, options)

      assert pixel.warm_temperature == 3000
      assert pixel.cool_temperature == 6500
    end
  end

  describe "RGBWW.to_srgb/1" do
    test "round-trips saturated red exactly" do
      {:ok, red} = Color.new("#ff0000")
      pixel = LED.RGBWW.from_srgb(red, chip: :ws2805)
      {:ok, back} = LED.RGBWW.to_srgb(pixel)

      assert_in_delta back.r, 1.0, 1.0e-6
      assert_in_delta back.g, 0.0, 1.0e-6
      assert_in_delta back.b, 0.0, 1.0e-6
    end

    test "round-trips a mid-grey closely" do
      {:ok, grey} = Color.new("#808080")
      pixel = LED.RGBWW.from_srgb(grey, chip: :ws2805)
      {:ok, back} = LED.RGBWW.to_srgb(pixel)

      assert_in_delta back.r, grey.r, 5.0e-3
      assert_in_delta back.g, grey.g, 5.0e-3
      assert_in_delta back.b, grey.b, 5.0e-3
    end
  end

  describe "RGBWW.to_xyz/1" do
    test "returns a Color.XYZ struct" do
      {:ok, srgb} = Color.new("#336699")
      pixel = LED.RGBWW.from_srgb(srgb, chip: :ws2805)
      assert {:ok, %Color.XYZ{}} = LED.RGBWW.to_xyz(pixel)
    end
  end
end
