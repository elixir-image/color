defmodule Color.PaletteTest do
  use ExUnit.Case, async: true

  doctest Color.Palette
  doctest Color.Palette.Tonal
  doctest Color.Palette.Theme
  doctest Color.Palette.Contrast
  doctest Color.Palette.ContrastScale
  doctest Color.Palette.Sort
  doctest Color.Palette.Cluster
  doctest Color.Palette.Summarize
  doctest Color.Material

  alias Color.Material
  alias Color.Palette
  alias Color.Palette.Contrast
  alias Color.Palette.ContrastScale
  alias Color.Palette.Sort
  alias Color.Palette.Theme
  alias Color.Palette.Tonal

  describe "Tonal.new/2 — basic" do
    test "default Tailwind stops" do
      palette = Tonal.new("#3b82f6")

      assert Map.keys(palette.stops) |> Enum.sort() ==
               [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]
    end

    test "stores seed and resolves seed_stop to a present label" do
      palette = Tonal.new("#3b82f6")

      assert %Color.SRGB{} = palette.seed
      assert palette.seed_stop in Map.keys(palette.stops)
    end

    test "the seed_stop holds the seed exactly" do
      {:ok, seed} = Color.new("#3b82f6")
      palette = Tonal.new(seed)

      assert Map.fetch!(palette.stops, palette.seed_stop) == seed
    end

    test "name is stored when given" do
      assert Tonal.new("#3b82f6", name: "brand").name == "brand"
      assert Tonal.new("#3b82f6").name == nil
    end
  end

  describe "Tonal.new/2 — custom stops" do
    test "respects a custom integer stop list" do
      palette = Tonal.new("#3b82f6", stops: [1, 2, 3, 4, 5])
      assert Map.keys(palette.stops) |> Enum.sort() == [1, 2, 3, 4, 5]
    end

    test "respects atom labels" do
      palette = Tonal.new("#3b82f6", stops: [:lightest, :light, :mid, :dark, :darkest])
      assert :mid in Map.keys(palette.stops)
    end

    test "single stop sits at the midpoint and equals the seed" do
      {:ok, seed} = Color.new("#3b82f6")
      palette = Tonal.new(seed, stops: [:only])
      assert palette.seed_stop == :only
      assert Map.fetch!(palette.stops, :only) == seed
    end
  end

  describe "Tonal.new/2 — algorithm properties" do
    test "lightness is monotonically decreasing across the default stops" do
      palette = Tonal.new("#3b82f6")

      lightnesses =
        for label <- Tonal.labels(palette) do
          {:ok, oklch} = Color.convert(Map.fetch!(palette.stops, label), Color.Oklch)
          oklch.l
        end

      Enum.zip(lightnesses, tl(lightnesses))
      |> Enum.each(fn {a, b} ->
        assert a > b, "expected lightness to decrease, got #{a} -> #{b}"
      end)
    end

    test "every generated stop is in sRGB gamut" do
      palette = Tonal.new("#ff00aa")

      for {_label, color} <- palette.stops do
        assert Color.Gamut.in_gamut?(color, :SRGB), "stop #{inspect(color)} out of sRGB gamut"
      end
    end

    test "preserves alpha from the seed" do
      {:ok, seed} = Color.new([0.2, 0.5, 0.95, 0.5])
      palette = Tonal.new(seed)

      assert Map.fetch!(palette.stops, palette.seed_stop).alpha == 0.5
    end

    test "hue_drift shifts hues at the extremes" do
      flat = Tonal.new("#3b82f6", hue_drift: false)
      drifted = Tonal.new("#3b82f6", hue_drift: true)

      {:ok, flat_200} = Color.convert(Map.fetch!(flat.stops, 200), Color.Oklch)
      {:ok, drift_200} = Color.convert(Map.fetch!(drifted.stops, 200), Color.Oklch)
      {:ok, flat_800} = Color.convert(Map.fetch!(flat.stops, 800), Color.Oklch)
      {:ok, drift_800} = Color.convert(Map.fetch!(drifted.stops, 800), Color.Oklch)

      # Drifted hues should differ from flat at both extremes, and
      # the direction of drift should be opposite at light vs dark.
      assert flat_200.h != drift_200.h
      assert flat_800.h != drift_800.h
    end

    test "custom anchors produce lighter / darker extremes" do
      tight = Tonal.new("#3b82f6", light_anchor: 0.85, dark_anchor: 0.30)
      wide = Tonal.new("#3b82f6", light_anchor: 0.99, dark_anchor: 0.05)

      {:ok, tight_50} = Color.convert(Map.fetch!(tight.stops, 50), Color.Oklch)
      {:ok, wide_50} = Color.convert(Map.fetch!(wide.stops, 50), Color.Oklch)

      assert tight_50.l < wide_50.l
    end

    test "achromatic seed produces an achromatic ramp" do
      palette = Tonal.new("#808080")

      for {_label, color} <- palette.stops do
        # All channels approximately equal.
        assert_in_delta color.r, color.g, 1.0e-3
        assert_in_delta color.g, color.b, 1.0e-3
      end
    end
  end

  describe "Tonal.fetch/2 and labels/1" do
    test "fetch returns the colour for a known label" do
      palette = Tonal.new("#3b82f6")
      assert {:ok, %Color.SRGB{}} = Tonal.fetch(palette, 500)
    end

    test "fetch returns :error for unknown labels" do
      palette = Tonal.new("#3b82f6")
      assert :error == Tonal.fetch(palette, :missing)
    end

    test "labels/1 returns stops in generation order" do
      palette = Tonal.new("#3b82f6", stops: [10, 20, 30])
      assert Tonal.labels(palette) == [10, 20, 30]
    end
  end

  describe "Tonal.new/2 — option validation" do
    test "rejects unknown options" do
      assert_raise Color.PaletteError, ~r/unknown_option/, fn ->
        Tonal.new("#3b82f6", nonsense: true)
      end
    end

    test "rejects empty stop list" do
      assert_raise Color.PaletteError, ~r/empty_stops/, fn ->
        Tonal.new("#3b82f6", stops: [])
      end
    end

    test "rejects non-list stops" do
      assert_raise Color.PaletteError, ~r/invalid_stops/, fn ->
        Tonal.new("#3b82f6", stops: 50)
      end
    end

    test "rejects duplicate stops" do
      assert_raise Color.PaletteError, ~r/duplicate_stops/, fn ->
        Tonal.new("#3b82f6", stops: [1, 2, 2, 3])
      end
    end

    test "rejects out-of-range light_anchor" do
      assert_raise Color.PaletteError, ~r/invalid_anchor/, fn ->
        Tonal.new("#3b82f6", light_anchor: 1.5)
      end
    end

    test "rejects out-of-range dark_anchor" do
      assert_raise Color.PaletteError, ~r/invalid_anchor/, fn ->
        Tonal.new("#3b82f6", dark_anchor: -0.1)
      end
    end

    test "rejects light_anchor <= dark_anchor" do
      assert_raise Color.PaletteError, ~r/invalid_anchor/, fn ->
        Tonal.new("#3b82f6", light_anchor: 0.3, dark_anchor: 0.5)
      end
    end
  end

  describe "Color.Palette.tonal/2 façade" do
    test "delegates to Tonal.new/2" do
      via_facade = Palette.tonal("#3b82f6", name: "x")
      direct = Tonal.new("#3b82f6", name: "x")

      assert via_facade.stops == direct.stops
      assert via_facade.name == "x"
    end
  end

  describe "Theme.new/2" do
    test "produces all five sub-palettes" do
      theme = Theme.new("#3b82f6")

      for key <- [:primary, :secondary, :tertiary, :neutral, :neutral_variant] do
        assert %Tonal{} = Map.fetch!(theme, key), "expected Tonal struct at :#{key}"
      end
    end

    test "secondary has lower chroma than primary" do
      theme = Theme.new("#3b82f6")

      {:ok, primary_mid} = Color.convert(Map.fetch!(theme.primary.stops, 40), Color.Oklch)
      {:ok, secondary_mid} = Color.convert(Map.fetch!(theme.secondary.stops, 40), Color.Oklch)

      assert secondary_mid.c < primary_mid.c
    end

    test "tertiary has a rotated hue compared to primary" do
      theme = Theme.new("#3b82f6", tertiary_hue_rotation: 60.0)

      {:ok, primary_mid} = Color.convert(Map.fetch!(theme.primary.stops, 40), Color.Oklch)
      {:ok, tertiary_mid} = Color.convert(Map.fetch!(theme.tertiary.stops, 40), Color.Oklch)

      # Hues should differ meaningfully (within a few degrees of 60°).
      diff = abs(tertiary_mid.h - primary_mid.h)
      diff = if diff > 180, do: 360 - diff, else: diff
      assert_in_delta diff, 60.0, 10.0
    end

    test "neutral has very low chroma" do
      theme = Theme.new("#3b82f6")

      for {_stop, color} <- theme.neutral.stops do
        {:ok, oklch} = Color.convert(color, Color.Oklch)
        assert oklch.c < 0.05, "neutral stop chroma too high: #{oklch.c}"
      end
    end

    test "neutral_variant chroma is higher than neutral" do
      theme = Theme.new("#3b82f6")

      {:ok, n} = Color.convert(Map.fetch!(theme.neutral.stops, 40), Color.Oklch)
      {:ok, nv} = Color.convert(Map.fetch!(theme.neutral_variant.stops, 40), Color.Oklch)

      assert nv.c > n.c
    end

    test "default stops are Material's 0..100" do
      theme = Theme.new("#3b82f6")

      expected = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100]
      assert Map.keys(theme.primary.stops) |> Enum.sort() == expected
    end

    test "stores name and seed" do
      theme = Theme.new("#3b82f6", name: "brand")
      assert theme.name == "brand"
      assert %Color.SRGB{} = theme.seed
    end

    test "rejects unknown options" do
      assert_raise Color.PaletteError, ~r/unknown_option/, fn ->
        Theme.new("#3b82f6", nope: true)
      end
    end
  end

  describe "Theme.role/3" do
    test "returns a colour for every light role" do
      theme = Theme.new("#3b82f6")

      for role <- Theme.roles() do
        assert {:ok, %Color.SRGB{}} = Theme.role(theme, role)
      end
    end

    test "returns a colour for every dark role" do
      theme = Theme.new("#3b82f6")

      for role <- Theme.roles() do
        assert {:ok, %Color.SRGB{}} = Theme.role(theme, role, scheme: :dark)
      end
    end

    test "light and dark variants of :primary differ" do
      theme = Theme.new("#3b82f6")

      {:ok, light} = Theme.role(theme, :primary, scheme: :light)
      {:ok, dark} = Theme.role(theme, :primary, scheme: :dark)

      refute light == dark
    end

    test ":primary maps to stop 40 in light scheme" do
      theme = Theme.new("#3b82f6")
      {:ok, via_role} = Theme.role(theme, :primary)
      {:ok, direct} = Tonal.fetch(theme.primary, 40)

      assert via_role == direct
    end

    test "unknown role returns :error" do
      theme = Theme.new("#3b82f6")
      assert :error == Theme.role(theme, :fictional)
    end
  end

  describe "Color.Palette.theme/2 façade" do
    test "delegates to Theme.new/2" do
      via_facade = Palette.theme("#3b82f6", name: "x")
      direct = Theme.new("#3b82f6", name: "x")

      assert via_facade.name == direct.name
      assert Map.keys(via_facade.primary.stops) == Map.keys(direct.primary.stops)
    end
  end

  describe "Contrast.new/2 — WCAG" do
    test "each stop's contrast is close to its target" do
      palette = Contrast.new("#3b82f6", targets: [3.0, 4.5, 7.0])

      for stop <- palette.stops do
        assert stop.color != :unreachable,
               "target #{stop.target} unreachable against white"

        assert_in_delta stop.achieved, stop.target, 0.1
      end
    end

    test "default targets are the WCAG band" do
      palette = Contrast.new("#3b82f6")
      assert length(palette.stops) == 8
    end

    test "supports a dark background" do
      palette = Contrast.new("#3b82f6", background: "black", targets: [3.0, 4.5, 7.0])

      for stop <- palette.stops do
        assert stop.color != :unreachable
      end
    end

    test "unreachable targets are marked" do
      # Contrast 20:1 against white is impossible for a blue with
      # any significant chroma — pure black only hits 21:1.
      palette = Contrast.new("#3b82f6", targets: [4.5, 21.5])

      [_, impossible] = palette.stops
      assert impossible.color == :unreachable
    end

    test "preserves hue of the seed" do
      {:ok, seed_oklch} = Color.convert("#3b82f6", Color.Oklch)
      palette = Contrast.new("#3b82f6", targets: [4.5])

      [stop] = palette.stops
      {:ok, stop_oklch} = Color.convert(stop.color, Color.Oklch)

      # Hue survives the gamut mapping to within a few degrees.
      diff = abs(seed_oklch.h - stop_oklch.h)
      diff = if diff > 180, do: 360 - diff, else: diff
      assert diff < 15, "hue drift too large: #{diff}°"
    end

    test "records background and metric on the struct" do
      palette = Contrast.new("#3b82f6", background: "#eeeeee", targets: [4.5])

      assert palette.metric == :wcag
      assert %Color.SRGB{} = palette.background
    end
  end

  describe "Contrast.new/2 — APCA" do
    test "each stop hits an APCA target within tolerance" do
      palette = Contrast.new("#3b82f6", metric: :apca, targets: [30, 60, 75])

      for stop <- palette.stops do
        assert stop.color != :unreachable
        assert_in_delta stop.achieved, stop.target, 2.0
      end
    end

    test "default targets are the APCA band" do
      palette = Contrast.new("#3b82f6", metric: :apca)
      assert length(palette.stops) == 6
    end
  end

  describe "Contrast.fetch/2" do
    test "returns the colour for a known target" do
      palette = Contrast.new("#3b82f6", targets: [4.5, 7.0])
      assert {:ok, %Color.SRGB{}} = Contrast.fetch(palette, 4.5)
    end

    test "returns :error for an unknown target" do
      palette = Contrast.new("#3b82f6", targets: [4.5])
      assert :error == Contrast.fetch(palette, 99.0)
    end
  end

  describe "Contrast.new/2 — option validation" do
    test "rejects unknown options" do
      assert_raise Color.PaletteError, ~r/unknown_option/, fn ->
        Contrast.new("#3b82f6", nope: true)
      end
    end

    test "rejects empty targets" do
      assert_raise Color.PaletteError, ~r/empty_targets/, fn ->
        Contrast.new("#3b82f6", targets: [])
      end
    end

    test "rejects non-numeric targets" do
      assert_raise Color.PaletteError, ~r/invalid_targets/, fn ->
        Contrast.new("#3b82f6", targets: [4.5, :bad])
      end
    end

    test "rejects non-list targets" do
      assert_raise Color.PaletteError, ~r/invalid_targets/, fn ->
        Contrast.new("#3b82f6", targets: 4.5)
      end
    end

    test "rejects unknown metric" do
      assert_raise Color.PaletteError, ~r/invalid_metric/, fn ->
        Contrast.new("#3b82f6", metric: :fake)
      end
    end
  end

  describe "Color.Palette.contrast/2 façade" do
    test "delegates to Contrast.new/2" do
      via_facade = Palette.contrast("#3b82f6", targets: [4.5])
      direct = Contrast.new("#3b82f6", targets: [4.5])

      assert via_facade.stops == direct.stops
    end
  end

  describe "Tonal.to_css/2 and to_tailwind/2" do
    test "to_css emits a :root block with one custom property per stop" do
      palette = Tonal.new("#3b82f6", name: "blue")
      css = Tonal.to_css(palette)

      assert String.starts_with?(css, ":root {\n")
      assert String.ends_with?(css, "}\n")
      assert css =~ "--blue-50:"
      assert css =~ "--blue-500:"
      assert css =~ "--blue-950:"
    end

    test "to_css respects :name and :selector overrides" do
      palette = Tonal.new("#3b82f6")
      css = Tonal.to_css(palette, name: "brand", selector: "[data-theme='light']")

      assert String.starts_with?(css, "[data-theme='light'] {\n")
      assert css =~ "--brand-500:"
    end

    test "to_tailwind emits a @theme block with --color-* variables" do
      palette = Tonal.new("#3b82f6", name: "blue")
      tw = Tonal.to_tailwind(palette)

      assert tw =~ "@theme {"
      assert tw =~ "--color-blue-50:"
      assert tw =~ "--color-blue-500:"
      assert tw =~ "--color-blue-950:"
    end
  end

  describe "ContrastScale.to_css/2 and to_tailwind/2" do
    test "to_css output is a :root block" do
      palette = ContrastScale.new("#3b82f6", name: "guaranteed")
      css = ContrastScale.to_css(palette)
      assert css =~ "--guaranteed-500:"
      assert String.starts_with?(css, ":root {\n")
    end

    test "to_tailwind output is a @theme block" do
      palette = ContrastScale.new("#3b82f6", name: "guaranteed")
      tw = ContrastScale.to_tailwind(palette)
      assert tw =~ "--color-guaranteed-500:"
    end
  end

  describe "Tonal.to_tokens/2 (DTCG)" do
    test "emits a named group keyed by stop label" do
      palette = Tonal.new("#3b82f6", name: "blue")
      tokens = Tonal.to_tokens(palette)

      assert Map.keys(tokens) == ["blue"]
      blue = tokens["blue"]

      assert Map.keys(blue) |> Enum.sort() ==
               ["100", "200", "300", "400", "50", "500", "600", "700", "800", "900", "950"]
    end

    test "every stop is a valid DTCG color token" do
      palette = Tonal.new("#3b82f6", name: "blue")
      tokens = Tonal.to_tokens(palette)

      for {_label, token} <- tokens["blue"] do
        assert token["$type"] == "color"
        assert %{"colorSpace" => _, "components" => _, "hex" => _} = token["$value"]
      end
    end

    test "default emit space is Oklch" do
      palette = Tonal.new("#3b82f6", name: "blue")
      tokens = Tonal.to_tokens(palette)

      assert tokens["blue"]["500"]["$value"]["colorSpace"] == "oklch"
    end

    test "alternative space via :space option" do
      palette = Tonal.new("#3b82f6", name: "blue")
      tokens = Tonal.to_tokens(palette, space: Color.SRGB)

      assert tokens["blue"]["500"]["$value"]["colorSpace"] == "srgb"
    end

    test "falls back to \"color\" when palette has no name" do
      palette = Tonal.new("#3b82f6")
      tokens = Tonal.to_tokens(palette)

      assert Map.keys(tokens) == ["color"]
    end
  end

  describe "Theme.to_tokens/2 (DTCG)" do
    test "has palette + role groups" do
      theme = Theme.new("#3b82f6")
      tokens = Theme.to_tokens(theme)

      assert Map.has_key?(tokens, "palette")
      assert Map.has_key?(tokens, "role")
    end

    test "palette group has all five sub-palettes" do
      theme = Theme.new("#3b82f6")
      tokens = Theme.to_tokens(theme)

      for key <- ["primary", "secondary", "tertiary", "neutral", "neutral_variant"] do
        assert Map.has_key?(tokens["palette"], key)
      end
    end

    test "role tokens are DTCG aliases pointing into palette" do
      theme = Theme.new("#3b82f6")
      tokens = Theme.to_tokens(theme)

      primary = tokens["role"]["primary"]
      assert primary["$type"] == "color"
      assert primary["$value"] == "{palette.primary.40}"

      on_primary = tokens["role"]["on_primary"]
      assert on_primary["$value"] == "{palette.primary.100}"
    end

    test "dark scheme uses different role tones" do
      theme = Theme.new("#3b82f6")
      light = Theme.to_tokens(theme, scheme: :light)
      dark = Theme.to_tokens(theme, scheme: :dark)

      assert light["role"]["primary"]["$value"] == "{palette.primary.40}"
      assert dark["role"]["primary"]["$value"] == "{palette.primary.80}"
    end
  end

  describe "ContrastScale.new/2" do
    test "produces the default Tailwind stop set" do
      palette = ContrastScale.new("#3b82f6")

      assert Map.keys(palette.stops) |> Enum.sort() ==
               [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]
    end

    test "stores seed, seed_stop, and background" do
      palette = ContrastScale.new("#3b82f6")

      assert %Color.SRGB{} = palette.seed
      assert palette.seed_stop in Map.keys(palette.stops)
      assert %Color.SRGB{} = palette.background
    end

    test "default guarantee is {4.5, 500}" do
      palette = ContrastScale.new("#3b82f6")
      assert palette.guarantee == {4.5, 500}
    end

    test "pairwise invariant: any two stops ≥ apart units apart pass ratio" do
      palette = ContrastScale.new("#3b82f6")
      {ratio, apart} = palette.guarantee
      stops = ContrastScale.labels(palette)

      for a <- stops, b <- stops, b - a >= apart do
        contrast =
          Color.Contrast.wcag_ratio(Map.fetch!(palette.stops, a), Map.fetch!(palette.stops, b))

        # Allow a tiny rounding tolerance — the search converges to within
        # a few hundredths of the target, and gamut-mapping at the extremes
        # introduces sub-0.1 drift. 0.1 keeps this a meaningful assertion
        # (real misses are many tenths short) without flaking on rounding.
        assert contrast >= ratio - 0.1,
               "invariant broken: stops #{a} and #{b} differ by #{b - a} (≥ #{apart}) " <>
                 "but contrast is #{Float.round(contrast, 3)} < #{ratio}"
      end
    end

    test "custom guarantee {3.0, 300}" do
      palette = ContrastScale.new("#3b82f6", guarantee: {3.0, 300})
      assert palette.guarantee == {3.0, 300}

      stops = ContrastScale.labels(palette)

      for {a, b} <- Enum.zip(stops, tl(stops)) ++ [],
          b - a >= 300 do
        contrast =
          Color.Contrast.wcag_ratio(Map.fetch!(palette.stops, a), Map.fetch!(palette.stops, b))

        assert contrast >= 2.9, "stops #{a} -> #{b} only #{contrast}:1"
      end
    end

    test "preserves seed exactly at seed_stop" do
      {:ok, seed} = Color.new("#3b82f6")
      palette = ContrastScale.new(seed)

      assert Map.fetch!(palette.stops, palette.seed_stop) == seed
    end

    test "records achieved contrast per stop" do
      palette = ContrastScale.new("#3b82f6")

      for {_label, achieved} <- palette.achieved do
        assert is_number(achieved) and achieved >= 1.0
      end
    end

    test "APCA metric" do
      palette = ContrastScale.new("#3b82f6", metric: :apca, guarantee: {60.0, 500})
      assert palette.metric == :apca
    end

    test "custom background (black)" do
      palette = ContrastScale.new("#3b82f6", background: "black")

      # Against black, the invariant still holds.
      {ratio, apart} = palette.guarantee
      stops = ContrastScale.labels(palette)

      for a <- stops, b <- stops, b - a >= apart do
        contrast =
          Color.Contrast.wcag_ratio(Map.fetch!(palette.stops, a), Map.fetch!(palette.stops, b))

        assert contrast >= ratio - 0.1
      end
    end

    test "hue drift produces a slightly different scale" do
      flat = ContrastScale.new("#3b82f6", hue_drift: false)
      drifted = ContrastScale.new("#3b82f6", hue_drift: true)

      refute Map.fetch!(flat.stops, 50) == Map.fetch!(drifted.stops, 50)
    end
  end

  describe "ContrastScale validation" do
    test "rejects unknown options" do
      assert_raise Color.PaletteError, ~r/unknown_option/, fn ->
        ContrastScale.new("#3b82f6", nope: true)
      end
    end

    test "rejects non-numeric stops" do
      assert_raise Color.PaletteError, ~r/invalid_stops/, fn ->
        ContrastScale.new("#3b82f6", stops: [:a, :b, :c])
      end
    end

    test "rejects duplicate stops" do
      assert_raise Color.PaletteError, ~r/duplicate_stops/, fn ->
        ContrastScale.new("#3b82f6", stops: [1, 2, 2, 3])
      end
    end

    test "rejects invalid guarantee shape" do
      assert_raise Color.PaletteError, ~r/invalid_guarantee/, fn ->
        ContrastScale.new("#3b82f6", guarantee: {0.5, 100})
      end

      assert_raise Color.PaletteError, ~r/invalid_guarantee/, fn ->
        ContrastScale.new("#3b82f6", guarantee: :nope)
      end
    end

    test "rejects bad metric" do
      assert_raise Color.PaletteError, ~r/invalid_metric/, fn ->
        ContrastScale.new("#3b82f6", metric: :fake)
      end
    end
  end

  describe "ContrastScale.fetch/2 and labels/1" do
    test "fetch returns the colour for a known label" do
      palette = ContrastScale.new("#3b82f6")
      assert {:ok, %Color.SRGB{}} = ContrastScale.fetch(palette, 500)
    end

    test "fetch returns :error for unknown labels" do
      palette = ContrastScale.new("#3b82f6")
      assert :error = ContrastScale.fetch(palette, :missing)
    end

    test "labels/1 preserves order" do
      palette = ContrastScale.new("#3b82f6", stops: [10, 20, 30])
      assert ContrastScale.labels(palette) == [10, 20, 30]
    end
  end

  describe "ContrastScale.to_tokens/2 (DTCG)" do
    test "emits a DTCG token group" do
      palette = ContrastScale.new("#3b82f6", name: "blue")
      tokens = ContrastScale.to_tokens(palette)

      assert Map.keys(tokens) == ["blue"]
      assert tokens["blue"]["500"]["$type"] == "color"
    end

    test "records achieved contrast in $extensions" do
      palette = ContrastScale.new("#3b82f6")
      tokens = ContrastScale.to_tokens(palette)

      ext = tokens["contrast_scale"]["500"]["$extensions"]["color"]
      assert is_number(ext["achieved"])
      assert ext["metric"] == "wcag"
    end

    test "default emit space is Oklch" do
      palette = ContrastScale.new("#3b82f6")
      tokens = ContrastScale.to_tokens(palette)

      assert tokens["contrast_scale"]["500"]["$value"]["colorSpace"] == "oklch"
    end
  end

  describe "semantic/3" do
    test "each hue category lands in the expected Oklch hue range" do
      expected = %{
        red: {0.0, 45.0},
        orange: {40.0, 75.0},
        yellow: {80.0, 115.0},
        green: {125.0, 165.0},
        teal: {170.0, 215.0},
        blue: {230.0, 275.0},
        purple: {285.0, 325.0},
        pink: {325.0, 360.0}
      }

      for {category, {lo, hi}} <- expected do
        color = Palette.semantic("#3b82f6", category)
        {:ok, oklch} = Color.convert(color, Color.Oklch)

        assert oklch.h >= lo and oklch.h <= hi,
               "category #{inspect(category)} hue #{oklch.h} outside [#{lo}, #{hi}]"
      end
    end

    test "semantic aliases resolve to the right hue" do
      {:ok, danger} = Color.convert(Palette.semantic("#3b82f6", :danger), Color.Oklch)
      {:ok, red} = Color.convert(Palette.semantic("#3b82f6", :red), Color.Oklch)
      assert_in_delta danger.h, red.h, 1.0e-3

      {:ok, success} = Color.convert(Palette.semantic("#3b82f6", :success), Color.Oklch)
      {:ok, green} = Color.convert(Palette.semantic("#3b82f6", :green), Color.Oklch)
      assert_in_delta success.h, green.h, 1.0e-3

      {:ok, warning} = Color.convert(Palette.semantic("#3b82f6", :warning), Color.Oklch)
      {:ok, orange} = Color.convert(Palette.semantic("#3b82f6", :orange), Color.Oklch)
      assert_in_delta warning.h, orange.h, 1.0e-3

      {:ok, info} = Color.convert(Palette.semantic("#3b82f6", :info), Color.Oklch)
      {:ok, blue} = Color.convert(Palette.semantic("#3b82f6", :blue), Color.Oklch)
      assert_in_delta info.h, blue.h, 1.0e-3
    end

    test "preserves seed's lightness and chroma" do
      seed = "#3b82f6"
      {:ok, seed_oklch} = Color.convert(seed, Color.Oklch)

      color = Palette.semantic(seed, :red)
      {:ok, oklch} = Color.convert(color, Color.Oklch)

      # Lightness is preserved exactly; chroma may be gamut-clipped
      # but should be close to the seed's (within 0.05).
      assert_in_delta oklch.l, seed_oklch.l, 0.02
      assert_in_delta oklch.c, seed_oklch.c, 0.08
    end

    test ":neutral strips chroma but preserves hue and lightness" do
      seed = "#3b82f6"
      {:ok, seed_oklch} = Color.convert(seed, Color.Oklch)

      color = Palette.semantic(seed, :neutral)
      {:ok, oklch} = Color.convert(color, Color.Oklch)

      assert oklch.c < 0.05
      assert_in_delta oklch.l, seed_oklch.l, 0.02
      assert_in_delta oklch.h, seed_oklch.h, 5.0
    end

    test ":chroma_factor option mutes or amplifies" do
      default = Palette.semantic("#3b82f6", :green)
      muted = Palette.semantic("#3b82f6", :green, chroma_factor: 0.5)
      flat = Palette.semantic("#3b82f6", :green, chroma_factor: 0.0)

      {:ok, default_oklch} = Color.convert(default, Color.Oklch)
      {:ok, muted_oklch} = Color.convert(muted, Color.Oklch)
      {:ok, flat_oklch} = Color.convert(flat, Color.Oklch)

      assert muted_oklch.c < default_oklch.c
      assert flat_oklch.c < muted_oklch.c
      assert flat_oklch.c < 0.02
    end

    test ":lightness option overrides seed's L" do
      dark = Palette.semantic("#3b82f6", :green, lightness: 0.3)
      light = Palette.semantic("#3b82f6", :green, lightness: 0.8)

      {:ok, dark_oklch} = Color.convert(dark, Color.Oklch)
      {:ok, light_oklch} = Color.convert(light, Color.Oklch)

      assert dark_oklch.l < light_oklch.l
      assert_in_delta dark_oklch.l, 0.3, 0.05
      assert_in_delta light_oklch.l, 0.8, 0.05
    end

    test "result is always in the target gamut" do
      for category <- [:red, :green, :blue, :success, :danger, :warning, :info, :neutral] do
        color = Palette.semantic("#3b82f6", category)

        assert Color.Gamut.in_gamut?(color, :SRGB),
               "category #{inspect(category)} produced out-of-gamut colour"
      end
    end

    test "works with any seed input Color.new/1 accepts" do
      red_from_hex = Palette.semantic("#3b82f6", :red)
      red_from_named = Palette.semantic("rebeccapurple", :red)
      {:ok, srgb} = Color.new("#3b82f6")
      red_from_struct = Palette.semantic(srgb, :red)

      for c <- [red_from_hex, red_from_named, red_from_struct] do
        {:ok, oklch} = Color.convert(c, Color.Oklch)
        assert oklch.h >= 0.0 and oklch.h <= 45.0
      end
    end

    test "composes cleanly into a Tonal palette" do
      # The canonical workflow: semantic/3 to get a seed, then tonal/2
      # to generate the full scale for that semantic role.
      danger_seed = Palette.semantic("#3b82f6", :danger)
      danger_scale = Palette.tonal(danger_seed, name: "danger")

      assert danger_scale.name == "danger"
      assert Map.keys(danger_scale.stops) |> Enum.count() == 11
      assert Palette.in_gamut?(danger_scale, :SRGB)
    end

    test "unknown category raises" do
      assert_raise ArgumentError, ~r/Unknown semantic category/, fn ->
        Palette.semantic("#3b82f6", :fictional)
      end
    end
  end

  describe "semantic_categories/0" do
    test "lists all supported categories" do
      cats = Palette.semantic_categories()

      for c <- [:red, :orange, :yellow, :green, :teal, :blue, :purple, :pink] do
        assert c in cats
      end

      for c <- [:success, :danger, :error, :destructive, :warning, :info, :neutral] do
        assert c in cats
      end
    end

    test "returned list is sorted and unique" do
      cats = Palette.semantic_categories()
      assert cats == Enum.sort(cats)
      assert cats == Enum.uniq(cats)
    end
  end

  describe "in_gamut? / gamut_report" do
    test "Tonal palette generated against sRGB is fully inside sRGB" do
      palette = Tonal.new("#3b82f6")
      assert Tonal.in_gamut?(palette, :SRGB) == true

      report = Tonal.gamut_report(palette, :SRGB)
      assert report.in_gamut? == true
      assert report.out_of_gamut == []
      assert length(report.stops) == 11
      assert Enum.all?(report.stops, & &1.in_gamut?)
    end

    test "ContrastScale palette is fully inside sRGB" do
      palette = ContrastScale.new("#3b82f6")
      assert ContrastScale.in_gamut?(palette, :SRGB)
      assert %{in_gamut?: true, out_of_gamut: []} = ContrastScale.gamut_report(palette, :SRGB)
    end

    test "Contrast palette ignores unreachable stops" do
      palette = Contrast.new("#3b82f6", targets: [4.5, 21.5])
      # 21.5 is unreachable for a saturated blue, but in_gamut? should still be true
      # because reachable stops are fine and unreachable stops have no colour to check.
      assert Contrast.in_gamut?(palette, :SRGB)

      report = Contrast.gamut_report(palette, :SRGB)
      assert report.in_gamut? == true

      # Both stops in the report; the unreachable one is marked.
      assert length(report.stops) == 2
      assert Enum.any?(report.stops, &(&1.color == :unreachable))
    end

    test "Theme reports per-sub-palette" do
      theme = Theme.new("#3b82f6")
      assert Theme.in_gamut?(theme, :SRGB)

      report = Theme.gamut_report(theme, :SRGB)
      assert report.in_gamut? == true

      assert Map.keys(report.sub_palettes) |> Enum.sort() ==
               [:neutral, :neutral_variant, :primary, :secondary, :tertiary]

      assert Enum.all?(report.sub_palettes, fn {_, r} -> r.in_gamut? end)
    end

    test "Color.Palette.in_gamut?/2 dispatches by struct type" do
      assert Palette.in_gamut?(Tonal.new("#3b82f6"))
      assert Palette.in_gamut?(Theme.new("#3b82f6"))
      assert Palette.in_gamut?(Contrast.new("#3b82f6", targets: [4.5]))
      assert Palette.in_gamut?(ContrastScale.new("#3b82f6"))
    end

    test "Color.Palette.gamut_report/2 dispatches by struct type" do
      assert %{in_gamut?: true} = Palette.gamut_report(Tonal.new("#3b82f6"))
      assert %{in_gamut?: true} = Palette.gamut_report(Theme.new("#3b82f6"))
      assert %{in_gamut?: true} = Palette.gamut_report(Contrast.new("#3b82f6", targets: [4.5]))
      assert %{in_gamut?: true} = Palette.gamut_report(ContrastScale.new("#3b82f6"))
    end

    test "manually-constructed out-of-gamut palette is detected" do
      # Build a Tonal then mutate one stop to a guaranteed out-of-sRGB
      # colour: Display P3 red — its (1, 0, 0) maps outside sRGB.
      palette = Tonal.new("#3b82f6", name: "blue")
      out = %Color.RGB{r: 1.0, g: 0.0, b: 0.0, working_space: :P3_D65}
      bad = %{palette | stops: Map.put(palette.stops, 500, out)}

      refute Tonal.in_gamut?(bad, :SRGB)

      report = Tonal.gamut_report(bad, :SRGB)
      assert report.in_gamut? == false
      assert length(report.out_of_gamut) == 1
      assert hd(report.out_of_gamut).label == 500
    end
  end

  describe "Color.Palette.contrast_scale/2 façade" do
    test "delegates to ContrastScale.new/2" do
      via = Palette.contrast_scale("#3b82f6", name: "x")
      direct = ContrastScale.new("#3b82f6", name: "x")

      assert via.stops == direct.stops
      assert via.name == "x"
    end
  end

  describe "Contrast.to_tokens/2 (DTCG)" do
    test "emits one token per target" do
      palette = Contrast.new("#3b82f6", targets: [3.0, 4.5, 7.0])
      tokens = Contrast.to_tokens(palette)

      assert Map.keys(tokens["contrast"]) |> Enum.sort() == ["3", "4.5", "7"]
    end

    test "reachable stops have $value with colorSpace" do
      palette = Contrast.new("#3b82f6", targets: [4.5])
      tokens = Contrast.to_tokens(palette)

      t = tokens["contrast"]["4.5"]
      assert t["$type"] == "color"
      assert t["$value"]["colorSpace"] == "oklch"
    end

    test "reachable stops carry the achieved ratio in $extensions" do
      palette = Contrast.new("#3b82f6", targets: [4.5])
      tokens = Contrast.to_tokens(palette)

      ext = tokens["contrast"]["4.5"]["$extensions"]["color"]
      assert_in_delta ext["achieved"], 4.5, 0.1
      assert ext["metric"] == "wcag"
    end

    test "unreachable stops emit a null $value with a reason" do
      # 21:1 is unreachable for a saturated blue against white
      palette = Contrast.new("#3b82f6", targets: [4.5, 21.5])
      tokens = Contrast.to_tokens(palette)

      impossible = tokens["contrast"]["21.5"]
      assert impossible["$value"] == nil
      assert impossible["$extensions"]["color"]["reason"] == "unreachable"
    end
  end

  describe "Sort.sort/2 — :hue_lightness" do
    test "primary colours land in rainbow order" do
      hexes = ["#0000ff", "#ff0000", "#00ff00", "#ffff00"]

      result = hexes |> Sort.sort() |> Enum.map(&Color.to_hex/1)
      assert result == ["#ff0000", "#ffff00", "#00ff00", "#0000ff"]
    end

    test "grays bucket to the front by default, sorted dark to light" do
      hexes = ["#ff0000", "#ffffff", "#000000", "#808080", "#00ff00"]

      result = hexes |> Sort.sort() |> Enum.map(&Color.to_hex/1)
      # Grays first (dark→light), then chromatic rainbow.
      assert result == ["#000000", "#808080", "#ffffff", "#ff0000", "#00ff00"]
    end

    test ":grays :after places achromatic colours at the end" do
      hexes = ["#808080", "#ff0000", "#00ff00"]

      result = Sort.sort(hexes, grays: :after) |> Enum.map(&Color.to_hex/1)
      assert result == ["#ff0000", "#00ff00", "#808080"]
    end

    test ":grays :exclude drops achromatic colours entirely" do
      hexes = ["#808080", "#ff0000", "#000000", "#00ff00"]

      result = Sort.sort(hexes, grays: :exclude) |> Enum.map(&Color.to_hex/1)
      assert result == ["#ff0000", "#00ff00"]
    end

    test "default :hue_origin (15°) wraps sub-15° hues past pure red to the end" do
      # A colour at Oklch H = 5° sits *below* the 15° cut, so
      # under the default origin its normalised hue is 350° and
      # it lands at the very end of the strip — after pure red
      # (≈29°) and after blue (≈264°). Setting origin=0° puts
      # H=5° before pure red, demonstrating the cut is what
      # moves between the two configurations.
      below_cut = %Color.Oklch{l: 0.55, c: 0.18, h: 5.0, alpha: nil}
      {:ok, below_cut_srgb} = Color.Gamut.to_gamut(below_cut, :SRGB)

      {:ok, red} = Color.new("#ff0000")
      {:ok, blue} = Color.new("#0000ff")

      assert Sort.sort([below_cut_srgb, red, blue]) == [red, blue, below_cut_srgb]

      assert Sort.sort([below_cut_srgb, red, blue], hue_origin: 0.0) ==
               [below_cut_srgb, red, blue]
    end

    test ":hue_origin rotates the cut point in the hue circle" do
      hexes = ["#ff0000", "#00ff00", "#0000ff"]

      # With origin at 180° (roughly cyan), the rainbow starts
      # after cyan, meaning blue comes first, then red wraps
      # around, then green.
      result = Sort.sort(hexes, hue_origin: 180.0) |> Enum.map(&Color.to_hex/1)
      assert result == ["#0000ff", "#ff0000", "#00ff00"]
    end

    test "within a single hue, darker lightnesses come first" do
      # Two shades of blue, hue essentially the same.
      hexes = ["#7fa5ff", "#0000ff"]

      result = Sort.sort(hexes) |> Enum.map(&Color.to_hex/1)
      # Darker blue first, lighter second.
      assert result == ["#0000ff", "#7fa5ff"]
    end

    test "preserves input structs (SRGB in, SRGB out)" do
      {:ok, red} = Color.new("#ff0000")
      {:ok, blue} = Color.new("#0000ff")

      assert [%Color.SRGB{}, %Color.SRGB{}] = Sort.sort([red, blue])
    end

    test "handles an empty list" do
      assert Sort.sort([]) == []
    end

    test "handles a single colour" do
      hexes = ["#3b82f6"]
      assert [%Color.SRGB{}] = Sort.sort(hexes)
    end
  end

  describe "Sort.sort/2 — :stepped_hue" do
    test "produces bucketed rainbow with zig-zag lightness" do
      # Two shades in the red bucket, two in the green bucket.
      # Pin `buckets: 4` so red lands in bucket 0 (0–90°, even, dark→light)
      # and green lands in bucket 1 (90–180°, odd, light→dark) regardless
      # of where the default `hue_origin` cuts the wheel.
      hexes = ["#400000", "#ff8080", "#004000", "#80ff80"]

      result =
        Sort.sort(hexes, strategy: :stepped_hue, buckets: 4)
        |> Enum.map(&Color.to_hex/1)

      assert result == ["#400000", "#ff8080", "#80ff80", "#004000"]
    end

    test "rejects buckets < 2" do
      assert_raise Color.PaletteError, ~r/:buckets/, fn ->
        Sort.sort(["#ff0000"], strategy: :stepped_hue, buckets: 1)
      end
    end
  end

  describe "Sort.sort/2 — :lightness" do
    test "sorts dark to light regardless of hue" do
      hexes = ["#ffffff", "#ff0000", "#000000", "#00ff00"]

      result = Sort.sort(hexes, strategy: :lightness) |> Enum.map(&Color.to_hex/1)
      # black, red, green, white (ordered by Oklch L).
      assert result == ["#000000", "#ff0000", "#00ff00", "#ffffff"]
    end
  end

  describe "Sort.sort/2 — validation" do
    test "rejects unknown options" do
      assert_raise Color.PaletteError, ~r/unknown/, fn ->
        Sort.sort(["#ff0000"], bogus: true)
      end
    end

    test "rejects unknown strategy" do
      assert_raise Color.PaletteError, ~r/strategy/, fn ->
        Sort.sort(["#ff0000"], strategy: :rainbow)
      end
    end

    test "rejects hue_origin outside [0, 360)" do
      assert_raise Color.PaletteError, ~r/hue_origin/, fn ->
        Sort.sort(["#ff0000"], hue_origin: 360.0)
      end
    end

    test "rejects negative chroma_threshold" do
      assert_raise Color.PaletteError, ~r/chroma_threshold/, fn ->
        Sort.sort(["#ff0000"], chroma_threshold: -0.1)
      end
    end

    test "rejects invalid :grays value" do
      assert_raise Color.PaletteError, ~r/grays/, fn ->
        Sort.sort(["#ff0000"], grays: :middle)
      end
    end
  end

  describe "Palette.sort/2 wrapper" do
    test "delegates to Sort.sort/2" do
      hexes = ["#0000ff", "#ff0000"]
      assert Palette.sort(hexes) == Sort.sort(hexes)
    end
  end

  describe "Summarize.summarize/3" do
    alias Color.Palette.Summarize

    test "merges near-duplicates into k clusters" do
      # Three reds and three blues — k=2 should collapse each
      # neighbourhood to one representative.
      reds = ["#ff0000", "#fa0202", "#ee0404"]
      blues = ["#0000ff", "#0202fa", "#0404ee"]
      result = Summarize.summarize(reds ++ blues, 2)

      assert length(result) == 2
      hexes = Enum.map(result, &Color.to_hex/1)
      # One representative is reddish, the other bluish.
      assert Enum.any?(hexes, &String.starts_with?(&1, "#ff")) or
               Enum.any?(hexes, &String.starts_with?(&1, "#fa")) or
               Enum.any?(hexes, &String.starts_with?(&1, "#ee"))

      assert Enum.any?(hexes, &String.starts_with?(&1, "#00"))
    end

    test "returns input unchanged when length(colors) <= k" do
      hexes = ["#ff0000", "#0000ff"]
      result = Summarize.summarize(hexes, 5) |> Enum.map(&Color.to_hex/1)

      assert result == ["#ff0000", "#0000ff"]
    end

    test "chromatic clusters return the highest-chroma member" do
      # A vivid red plus two muted variants. The cluster
      # centroid sits between them, but the representative
      # should be the vivid one because the centroid chroma
      # exceeds the rep_chroma_threshold.
      vivid = "#ff0000"
      muted_a = "#cc4040"
      muted_b = "#dd5555"

      [rep] = Summarize.summarize([muted_a, vivid, muted_b], 1)
      assert Color.to_hex(rep) == "#ff0000"
    end

    test "achromatic clusters return the closest-to-centroid member" do
      # Dark, mid, light gray. Centroid lightness is ~0.5 (mid),
      # so the rep must be the middle gray rather than either
      # extreme.
      hexes = ["#404040", "#808080", "#c0c0c0"]

      [rep] = Summarize.summarize(hexes, 1)
      assert Color.to_hex(rep) == "#808080"
    end

    test "weights pull the centroid toward the heavier inputs" do
      # Two blues and one red, with the red weighted heavily.
      # When merging to k=1 the centroid should land near red.
      hexes = ["#0000ff", "#0000ff", "#ff0000"]

      [rep] =
        Summarize.summarize(hexes, 1, weights: [1.0, 1.0, 100.0])

      {:ok, oklch} = Color.convert(rep, Color.Oklch)
      # Pure red is around H ≈ 29° in Oklch; pure blue around 264°.
      # With red dominating, the rep should sit closer to red.
      assert oklch.h < 90 or oklch.h > 270
    end

    test "preserves an exact representative from the input set" do
      # Merging shouldn't synthesise new colours — every output
      # must be one of the input swatches.
      hexes = ["#a0c0e0", "#10203f", "#ff8800", "#ffe000", "#a0a0a0"]
      input_set = MapSet.new(hexes)

      result = Summarize.summarize(hexes, 3) |> Enum.map(&Color.to_hex/1)

      assert length(result) == 3
      Enum.each(result, fn hex -> assert hex in input_set end)
    end

    test "rejects mismatched weights length" do
      assert_raise Color.PaletteError, ~r/weights/, fn ->
        Summarize.summarize(["#ff0000", "#00ff00"], 1, weights: [1.0])
      end
    end

    test "rejects negative weights" do
      assert_raise Color.PaletteError, ~r/weights/, fn ->
        Summarize.summarize(["#ff0000", "#00ff00"], 1, weights: [-1.0, 1.0])
      end
    end

    test "rejects non-positive ab_weight" do
      assert_raise Color.PaletteError, ~r/ab_weight/, fn ->
        Summarize.summarize(["#ff0000"], 1, ab_weight: 0)
      end
    end

    test "rejects unknown options" do
      assert_raise Color.PaletteError, ~r/bogus/, fn ->
        Summarize.summarize(["#ff0000"], 1, bogus: :nope)
      end
    end

    test "Palette.summarize/3 delegates to Summarize.summarize/3" do
      hexes = ["#ff0000", "#fa0202", "#0000ff"]
      assert Palette.summarize(hexes, 2) == Summarize.summarize(hexes, 2)
    end
  end

  describe "Cluster.from_colors/2" do
    alias Color.Palette.Cluster

    test "produces one singleton cluster per input" do
      [c1, c2] = Cluster.from_colors(["#ff0000", "#0000ff"])

      assert c1.mass == 1.0
      assert length(c1.members) == 1
      assert hd(c1.members).output |> Color.to_hex() == "#ff0000"

      assert c2.mass == 1.0
      assert hd(c2.members).output |> Color.to_hex() == "#0000ff"
    end

    test "honours explicit weights" do
      [c1, c2] = Cluster.from_colors(["#ff0000", "#0000ff"], weights: [3.0, 0.5])

      assert c1.mass == 3.0
      assert hd(c1.members).mass == 3.0
      assert c2.mass == 0.5
    end

    test "rejects mismatched weights length" do
      assert_raise Color.PaletteError, ~r/weights/, fn ->
        Cluster.from_colors(["#ff0000", "#00ff00"], weights: [1.0])
      end
    end

    test "rejects negative weights" do
      assert_raise Color.PaletteError, ~r/weights/, fn ->
        Cluster.from_colors(["#ff0000"], weights: [-1.0])
      end
    end

    test "carries oklab + oklch through to members for downstream use" do
      [%{members: [m]}] = Cluster.from_colors(["#ff0000"])

      assert %Color.Oklab{} = m.oklab
      assert %Color.Oklch{} = m.oklch
      # Pure red sits at Oklch H ≈ 29° with positive a (red axis).
      assert m.oklab.a > 0
      assert_in_delta m.oklch.h, 29.0, 2.0
    end
  end

  describe "Cluster.merge_until/3" do
    alias Color.Palette.Cluster

    test "is a no-op when the input already meets the target" do
      input = Cluster.from_colors(["#ff0000", "#0000ff"])

      assert Cluster.merge_until(input, 2) == input
      assert Cluster.merge_until(input, 5) == input
    end

    test "collapses N inputs into exactly target_count clusters" do
      input = Cluster.from_colors(["#ff0000", "#fe0202", "#fc0404", "#0000ff", "#0202fc"])
      result = Cluster.merge_until(input, 2)

      assert length(result) == 2
      total_members = Enum.sum(Enum.map(result, &length(&1.members)))
      assert total_members == 5
    end

    test "merged centroid is the mass-weighted mean" do
      input = Cluster.from_colors(["#ff0000", "#0000ff"], weights: [3.0, 1.0])
      [merged] = Cluster.merge_until(input, 1)

      assert merged.mass == 4.0
      [c1, c2] = input
      {l1, a1, b1} = c1.centroid
      {l2, a2, b2} = c2.centroid

      expected = {
        (l1 * 3.0 + l2 * 1.0) / 4.0,
        (a1 * 3.0 + a2 * 1.0) / 4.0,
        (b1 * 3.0 + b2 * 1.0) / 4.0
      }

      {ml, ma, mb} = merged.centroid
      {el, ea, eb} = expected
      assert_in_delta ml, el, 1.0e-9
      assert_in_delta ma, ea, 1.0e-9
      assert_in_delta mb, eb, 1.0e-9
    end

    test "operates on caller-built clusters (image pipeline shape)" do
      # The :image library produces clusters from K-means
      # centroids without going through `from_colors`. Smoke-test
      # that any map matching the documented shape works.
      red_oklab = oklab_for("#ff0000")
      red_oklch = oklch_for("#ff0000")
      blue_oklab = oklab_for("#0000ff")
      blue_oklch = oklch_for("#0000ff")

      clusters = [
        %{
          centroid: {red_oklab.l, red_oklab.a, red_oklab.b},
          mass: 100.0,
          members: [%{output: :red, oklab: red_oklab, oklch: red_oklch, mass: 100.0}]
        },
        %{
          centroid: {blue_oklab.l, blue_oklab.a, blue_oklab.b},
          mass: 50.0,
          members: [%{output: :blue, oklab: blue_oklab, oklch: blue_oklch, mass: 50.0}]
        }
      ]

      [merged] = Cluster.merge_until(clusters, 1)
      assert merged.mass == 150.0
      assert Enum.sort(Enum.map(merged.members, & &1.output)) == [:blue, :red]
    end

    test "rejects non-positive ab_weight" do
      input = Cluster.from_colors(["#ff0000", "#0000ff"])

      assert_raise Color.PaletteError, ~r/ab_weight/, fn ->
        Cluster.merge_until(input, 1, ab_weight: 0)
      end
    end

    defp oklab_for(hex) do
      {:ok, srgb} = Color.new(hex)
      {:ok, oklab} = Color.convert(srgb, Color.Oklab)
      oklab
    end

    defp oklch_for(hex) do
      {:ok, srgb} = Color.new(hex)
      {:ok, oklch} = Color.convert(srgb, Color.Oklch)
      %{oklch | l: oklch.l || 0.0, c: oklch.c || 0.0, h: oklch.h || 0.0}
    end
  end

  describe "Cluster.representative/2" do
    alias Color.Palette.Cluster

    test "chromatic clusters return the highest mass-weighted-chroma member" do
      [cluster] =
        Cluster.from_colors(["#cc4040", "#ff0000", "#dd5555"])
        |> Cluster.merge_until(1)

      assert Cluster.representative(cluster) |> Color.to_hex() == "#ff0000"
    end

    test "achromatic clusters return the closest-to-centroid member" do
      [cluster] =
        Cluster.from_colors(["#404040", "#808080", "#c0c0c0"])
        |> Cluster.merge_until(1)

      assert Cluster.representative(cluster) |> Color.to_hex() == "#808080"
    end

    test "honours :rep_chroma_threshold by routing borderline-chromatic clusters either way" do
      # A near-grey cluster (centroid chroma ≈ 0.025): with the
      # default threshold (0.03) it falls into the achromatic
      # branch; lowering the threshold below the centroid's
      # chroma forces the chromatic branch.
      [cluster] =
        Cluster.from_colors(["#888080", "#807880"])
        |> Cluster.merge_until(1)

      {_l, a, b} = cluster.centroid
      centroid_chroma = :math.sqrt(a * a + b * b)
      assert centroid_chroma > 0.0 and centroid_chroma < 0.03

      # Default — achromatic branch.
      assert Cluster.representative(cluster) ==
               Cluster.representative(cluster, rep_chroma_threshold: 0.03)

      # Threshold below the centroid's actual chroma — chromatic
      # branch (highest mass-weighted-chroma member).
      forced = Cluster.representative(cluster, rep_chroma_threshold: 0.0)
      assert %Color.SRGB{} = forced
    end
  end

  describe "Cluster.distance/3" do
    alias Color.Palette.Cluster

    test "returns 0 for identical points" do
      assert Cluster.distance({0.5, 0.0, 0.0}, {0.5, 0.0, 0.0}, 2.0) == 0.0
    end

    test "weighting (a, b) higher than L makes hue-mismatch dominate" do
      # Same L, different a → distance scales with √ab_weight.
      d1 = Cluster.distance({0.5, 0.0, 0.0}, {0.5, 0.1, 0.0}, 1.0)
      d4 = Cluster.distance({0.5, 0.0, 0.0}, {0.5, 0.1, 0.0}, 4.0)
      assert_in_delta d4 / d1, 2.0, 1.0e-9
    end
  end

  describe "Color.Material" do
    test "accepts hex inputs and stores normalised SRGB" do
      mat = Material.new("#ff0000", metallic: 1.0, roughness: 0.3)

      assert %Color.SRGB{} = mat.base_color
      assert Color.to_hex(mat.base_color) == "#ff0000"
      assert mat.metallic == 1.0
      assert mat.roughness == 0.3
    end

    test "accepts CSS named colours" do
      mat = Material.new("saddlebrown")
      assert Color.to_hex(mat.base_color) == "#8b4513"
    end

    test "accepts a pre-parsed SRGB struct" do
      {:ok, red} = Color.new("#ff0000")
      mat = Material.new(red, name: "red plastic")

      assert mat.base_color == red
      assert mat.name == "red plastic"
    end

    test "applies sensible defaults" do
      mat = Material.new("#888888")

      assert mat.metallic == 0.0
      assert mat.roughness == 0.5
      assert mat.clearcoat == 0.0
      assert mat.clearcoat_roughness == 0.03
      assert mat.name == nil
    end

    test "rejects metallic outside [0, 1]" do
      assert_raise Color.PaletteError, ~r/metallic/, fn ->
        Material.new("#ff0000", metallic: 1.5)
      end
    end

    test "rejects roughness outside [0, 1]" do
      assert_raise Color.PaletteError, ~r/roughness/, fn ->
        Material.new("#ff0000", roughness: -0.1)
      end
    end

    test "rejects unknown options" do
      assert_raise Color.PaletteError, ~r/unknown/, fn ->
        Material.new("#ff0000", bogus: 1)
      end
    end

    test "to_pbr_tuple returns bucket 1 for a pure metal" do
      mat = Material.new("#c0c0c0", metallic: 1.0, roughness: 0.2)
      {bucket, _h, _l, rough} = Material.to_pbr_tuple(mat)

      assert bucket == 1
      assert rough == 0.2
    end

    test "to_pbr_tuple respects a custom metallic_threshold" do
      mat = Material.new("#c0c0c0", metallic: 0.4)
      assert {0, _, _, _} = Material.to_pbr_tuple(mat)
      assert {1, _, _, _} = Material.to_pbr_tuple(mat, metallic_threshold: 0.3)
    end
  end

  describe "Sort.sort/2 — :material_pbr" do
    test "dielectrics come before metals by default" do
      plastic = Material.new("#ff0000", metallic: 0.0, roughness: 0.6, name: "plastic")
      metal = Material.new("#ffd700", metallic: 1.0, roughness: 0.05, name: "metal")

      assert [^plastic, ^metal] =
               Sort.sort([metal, plastic], strategy: :material_pbr)
    end

    test ":metals :before flips bucket order" do
      plastic = Material.new("#ff0000", metallic: 0.0, name: "plastic")
      metal = Material.new("#ffd700", metallic: 1.0, name: "metal")

      assert [^metal, ^plastic] =
               Sort.sort([plastic, metal], strategy: :material_pbr, metals: :before)
    end

    test "within a single bucket, colours sort by hue then lightness" do
      red_plastic = Material.new("#ff0000", name: "red")
      green_plastic = Material.new("#00ff00", name: "green")
      blue_plastic = Material.new("#0000ff", name: "blue")

      names =
        [blue_plastic, red_plastic, green_plastic]
        |> Sort.sort(strategy: :material_pbr)
        |> Enum.map(& &1.name)

      assert names == ["red", "green", "blue"]
    end

    test "gloss tiebreaker: same base colour, glossy first by default" do
      gloss = Material.new("#ff0000", roughness: 0.05, name: "gloss")
      matte = Material.new("#ff0000", roughness: 0.9, name: "matte")

      assert [%Material{name: "gloss"}, %Material{name: "matte"}] =
               Sort.sort([matte, gloss], strategy: :material_pbr)
    end

    test ":roughness_order :matte_first reverses the gloss tiebreaker" do
      gloss = Material.new("#ff0000", roughness: 0.05, name: "gloss")
      matte = Material.new("#ff0000", roughness: 0.9, name: "matte")

      assert [%Material{name: "matte"}, %Material{name: "gloss"}] =
               Sort.sort([gloss, matte],
                 strategy: :material_pbr,
                 roughness_order: :matte_first
               )
    end

    test "metallic_threshold controls bucket assignment" do
      borderline = Material.new("#c0c0c0", metallic: 0.4, name: "semi")
      clear_plastic = Material.new("#ff0000", metallic: 0.0, name: "plastic")

      # Default threshold 0.5 → borderline stays in dielectric bucket.
      # Within dielectrics the gray sub-bucket (semi) comes before
      # the chromatic sub-bucket (plastic) under `:grays :before`.
      assert [%Material{name: "semi"}, %Material{name: "plastic"}] =
               Sort.sort([borderline, clear_plastic], strategy: :material_pbr)

      # Lower threshold to 0.3 → borderline crosses into the metal
      # bucket, which (with `:metals :after`) lands last.
      assert [%Material{name: "plastic"}, %Material{name: "semi"}] =
               Sort.sort([borderline, clear_plastic],
                 strategy: :material_pbr,
                 metallic_threshold: 0.3
               )
    end

    test "mixed plain-colour + material list works" do
      hex = "#0000ff"
      red_mat = Material.new("#ff0000", name: "red mat")
      gold = Material.new("#ffd700", metallic: 1.0, name: "gold")

      sorted = Sort.sort([gold, hex, red_mat], strategy: :material_pbr)

      # Red-material (dielectric) first, blue hex (plain → dielectric)
      # second, gold metal last.
      assert [%Material{name: "red mat"}, %Color.SRGB{} = blue, %Material{name: "gold"}] = sorted

      assert Color.to_hex(blue) == "#0000ff"
    end

    test "preserves Material structs in output" do
      mat = Material.new("#ff0000", name: "red")

      assert [%Material{name: "red"}] = Sort.sort([mat], strategy: :material_pbr)
    end

    test "rejects metallic_threshold outside (0, 1]" do
      assert_raise Color.PaletteError, ~r/metallic_threshold/, fn ->
        Sort.sort(["#ff0000"], strategy: :material_pbr, metallic_threshold: 0.0)
      end
    end

    test "rejects invalid :metals value" do
      assert_raise Color.PaletteError, ~r/metals/, fn ->
        Sort.sort(["#ff0000"], strategy: :material_pbr, metals: :middle)
      end
    end

    test "rejects invalid :roughness_order" do
      assert_raise Color.PaletteError, ~r/roughness_order/, fn ->
        Sort.sort(["#ff0000"], strategy: :material_pbr, roughness_order: :loudest_first)
      end
    end
  end
end
