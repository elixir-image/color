defmodule Color.DesignTokensTest do
  use ExUnit.Case, async: true

  doctest Color.DesignTokens

  alias Color.DesignTokens
  alias Color.DesignTokensDecodeError

  describe "encode/2 — per-space" do
    test "sRGB" do
      {:ok, srgb} = Color.new("#3b82f6")
      token = DesignTokens.encode(srgb)

      assert token["colorSpace"] == "srgb"
      assert [r, g, b] = token["components"]
      assert_in_delta r, 0.2314, 1.0e-3
      assert_in_delta g, 0.5098, 1.0e-3
      assert_in_delta b, 0.9647, 1.0e-3
      assert token["hex"] == "#3b82f6"
    end

    test "Oklch via :space option" do
      token = DesignTokens.encode("#3b82f6", space: Color.Oklch)

      assert token["colorSpace"] == "oklch"
      assert [l, c, h] = token["components"]
      assert_in_delta l, 0.623, 1.0e-2
      assert_in_delta c, 0.188, 1.0e-2
      assert_in_delta h, 259.82, 1.0
    end

    test "Lab" do
      token = DesignTokens.encode("#3b82f6", space: Color.Lab)
      assert token["colorSpace"] == "lab"
      assert length(token["components"]) == 3
    end

    test "LCHab" do
      token = DesignTokens.encode("#3b82f6", space: Color.LCHab)
      assert token["colorSpace"] == "lch"
    end

    test "Oklab" do
      token = DesignTokens.encode("#3b82f6", space: Color.Oklab)
      assert token["colorSpace"] == "oklab"
    end

    test "HSL" do
      token = DesignTokens.encode("#3b82f6", space: Color.HSL)
      assert token["colorSpace"] == "hsl"
    end

    test "AdobeRGB" do
      token = DesignTokens.encode("#3b82f6", space: Color.AdobeRGB)
      assert token["colorSpace"] == "a98-rgb"
    end

    test "XYZ D65 (default)" do
      token = DesignTokens.encode("#3b82f6", space: Color.XYZ)
      assert token["colorSpace"] == "xyz-d65"
    end

    test "XYZ D50" do
      xyz_d50 = %Color.XYZ{x: 0.4, y: 0.4, z: 0.3, illuminant: :D50, observer_angle: 2}
      token = DesignTokens.encode(xyz_d50)
      assert token["colorSpace"] == "xyz-d50"
    end

    test "Display P3 via Color.RGB" do
      rgb = %Color.RGB{r: 0.5, g: 0.2, b: 0.8, working_space: :P3}
      token = DesignTokens.encode(rgb)
      assert token["colorSpace"] == "display-p3"
    end

    test "Rec2020 via Color.RGB" do
      rgb = %Color.RGB{r: 0.5, g: 0.2, b: 0.8, working_space: :Rec2020}
      token = DesignTokens.encode(rgb)
      assert token["colorSpace"] == "rec2020"
    end

    test "ProPhoto via Color.RGB" do
      rgb = %Color.RGB{r: 0.5, g: 0.2, b: 0.8, working_space: :ProPhoto}
      token = DesignTokens.encode(rgb)
      assert token["colorSpace"] == "prophoto-rgb"
    end

    test "alpha is preserved" do
      {:ok, srgb} = Color.new([1.0, 0.5, 0.2, 0.5])
      token = DesignTokens.encode(srgb)
      assert token["alpha"] == 0.5
    end

    test "hex fallback is always present" do
      for space <- [Color.Oklch, Color.Oklab, Color.Lab, Color.LCHab, Color.HSL] do
        token = DesignTokens.encode("#3b82f6", space: space)
        assert token["hex"] == "#3b82f6", "hex missing for #{inspect(space)}"
      end
    end

    test "encode_token wraps with $type + $value" do
      token = DesignTokens.encode_token("#3b82f6")
      assert token["$type"] == "color"
      assert %{"colorSpace" => "srgb"} = token["$value"]
    end
  end

  describe "decode/1 — per-space" do
    test "sRGB $value map" do
      {:ok, srgb} =
        DesignTokens.decode(%{"colorSpace" => "srgb", "components" => [0.23, 0.51, 0.96]})

      assert %Color.SRGB{r: 0.23, g: 0.51, b: 0.96, alpha: nil} = srgb
    end

    test "full token with $type/$value" do
      token = %{
        "$type" => "color",
        "$value" => %{"colorSpace" => "oklch", "components" => [0.63, 0.19, 260]}
      }

      {:ok, oklch} = DesignTokens.decode(token)
      assert %Color.Oklch{} = oklch
      assert oklch.l == 0.63
    end

    test "accepts alpha" do
      {:ok, srgb} =
        DesignTokens.decode(%{
          "colorSpace" => "srgb",
          "components" => [1, 0, 0],
          "alpha" => 0.5
        })

      assert srgb.alpha == 0.5
    end

    test "hex-only fallback" do
      {:ok, srgb} = DesignTokens.decode(%{"hex" => "#3b82f6"})
      assert Color.to_hex(srgb) == "#3b82f6"
    end

    test "all DTCG colour spaces" do
      cases = [
        {"srgb", [0.2, 0.5, 0.9], Color.SRGB},
        {"srgb-linear", [0.2, 0.5, 0.9], Color.RGB},
        {"hsl", [200, 0.5, 0.5], Color.HSL},
        {"lab", [50, 10, -20], Color.Lab},
        {"lch", [50, 30, 180], Color.LCHab},
        {"oklab", [0.6, 0.02, -0.15], Color.Oklab},
        {"oklch", [0.6, 0.15, 240], Color.Oklch},
        {"display-p3", [0.5, 0.2, 0.8], Color.RGB},
        {"rec2020", [0.5, 0.2, 0.8], Color.RGB},
        {"prophoto-rgb", [0.5, 0.2, 0.8], Color.RGB},
        {"a98-rgb", [0.5, 0.2, 0.8], Color.AdobeRGB},
        {"xyz-d65", [0.4, 0.4, 0.5], Color.XYZ},
        {"xyz-d50", [0.4, 0.4, 0.5], Color.XYZ},
        {"xyz", [0.4, 0.4, 0.5], Color.XYZ}
      ]

      for {space, components, expected_module} <- cases do
        {:ok, struct} =
          DesignTokens.decode(%{"colorSpace" => space, "components" => components})

        assert struct.__struct__ == expected_module,
               "decoded #{inspect(space)} → got #{inspect(struct.__struct__)} expected #{inspect(expected_module)}"
      end
    end
  end

  describe "decode/1 — errors" do
    test "unknown colour space" do
      assert {:error, %DesignTokensDecodeError{reason: :unknown_color_space}} =
               DesignTokens.decode(%{"colorSpace" => "fake", "components" => [0, 0, 0]})
    end

    test "alias string" do
      assert {:error, %DesignTokensDecodeError{reason: :alias_not_resolved}} =
               DesignTokens.decode("{palette.blue.500}")
    end

    test "wrong $type" do
      assert {:error, %DesignTokensDecodeError{reason: :not_a_color_token}} =
               DesignTokens.decode(%{"$type" => "dimension", "$value" => "16px"})
    end

    test "missing components" do
      assert {:error, %DesignTokensDecodeError{reason: :missing_field}} =
               DesignTokens.decode(%{"colorSpace" => "srgb"})
    end

    test "invalid alpha" do
      assert {:error, %DesignTokensDecodeError{reason: :bad_alpha}} =
               DesignTokens.decode(%{
                 "colorSpace" => "srgb",
                 "components" => [1, 0, 0],
                 "alpha" => 2.0
               })
    end

    test "bad hex-only fallback" do
      assert {:error, %DesignTokensDecodeError{reason: :bad_hex}} =
               DesignTokens.decode(%{"hex" => "not-a-hex"})
    end

    test "non-map input" do
      assert {:error, %DesignTokensDecodeError{reason: :not_a_color_token}} =
               DesignTokens.decode(123)
    end

    test "decode! raises" do
      assert_raise DesignTokensDecodeError, fn ->
        DesignTokens.decode!(%{"colorSpace" => "nope", "components" => [0, 0, 0]})
      end
    end
  end

  describe "round-trip" do
    test "srgb → decode → re-encode preserves hex" do
      original = %{"colorSpace" => "srgb", "components" => [0.231, 0.509, 0.965]}
      {:ok, struct} = DesignTokens.decode(original)
      re_encoded = DesignTokens.encode(struct)

      assert re_encoded["components"] == [0.231, 0.509, 0.965]
      assert re_encoded["hex"] == Color.to_hex(struct)
    end

    test "oklch round-trip" do
      original = %{"colorSpace" => "oklch", "components" => [0.63, 0.19, 260.0]}
      {:ok, struct} = DesignTokens.decode(original)
      re_encoded = DesignTokens.encode(struct)

      assert re_encoded["colorSpace"] == "oklch"
      assert_in_delta Enum.at(re_encoded["components"], 0), 0.63, 1.0e-6
      assert_in_delta Enum.at(re_encoded["components"], 1), 0.19, 1.0e-6
      assert_in_delta Enum.at(re_encoded["components"], 2), 260.0, 1.0e-6
    end

    test "alpha survives round-trip" do
      original = %{"colorSpace" => "srgb", "components" => [1, 0, 0], "alpha" => 0.5}
      {:ok, struct} = DesignTokens.decode(original)
      re_encoded = DesignTokens.encode(struct)

      assert re_encoded["alpha"] == 0.5
    end
  end
end
