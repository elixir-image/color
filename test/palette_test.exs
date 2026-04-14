defmodule Color.PaletteTest do
  use ExUnit.Case, async: true

  doctest Color.Palette
  doctest Color.Palette.Tonal
  doctest Color.Palette.Theme
  doctest Color.Palette.Contrast
  doctest Color.Palette.ContrastScale

  alias Color.Palette
  alias Color.Palette.Contrast
  alias Color.Palette.ContrastScale
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

    test "to_tailwind emits a theme.extend.colors block" do
      palette = Tonal.new("#3b82f6", name: "blue")
      tw = Tonal.to_tailwind(palette)

      assert tw =~ "theme: {"
      assert tw =~ "extend: {"
      assert tw =~ "blue: {"
      assert tw =~ "50: \"#"
      assert tw =~ "950: \"#"
    end
  end

  describe "ContrastScale.to_css/2 and to_tailwind/2" do
    test "to_css output is a :root block" do
      palette = ContrastScale.new("#3b82f6", name: "guaranteed")
      css = ContrastScale.to_css(palette)
      assert css =~ "--guaranteed-500:"
      assert String.starts_with?(css, ":root {\n")
    end

    test "to_tailwind output is a theme block" do
      palette = ContrastScale.new("#3b82f6", name: "guaranteed")
      tw = ContrastScale.to_tailwind(palette)
      assert tw =~ "guaranteed: {"
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
end
