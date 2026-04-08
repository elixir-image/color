# Conversion micro-benchmarks for the hot paths.
#
# Run with `mix run bench/conversions.exs`.

palette = [
  %Color.SRGB{r: 1.0, g: 0.0, b: 0.0},
  %Color.SRGB{r: 0.0, g: 1.0, b: 0.0},
  %Color.SRGB{r: 0.0, g: 0.0, b: 1.0},
  %Color.SRGB{r: 0.7, g: 0.5, b: 0.3},
  %Color.SRGB{r: 0.4, g: 0.2, b: 0.6},
  %Color.SRGB{r: 0.5, g: 0.5, b: 0.5}
]

single = hd(palette)

lab_pair = {
  %Color.Lab{l: 50.0, a: 2.6772, b: -79.7751},
  %Color.Lab{l: 50.0, a: 0.0, b: -82.7485}
}

p3_red = %Color.RGB{r: 1.0, g: 0.0, b: 0.0, working_space: :P3_D65}

Benchee.run(
  %{
    "convert: SRGB -> XYZ" => fn -> Color.convert(single, Color.XYZ) end,
    "convert: SRGB -> Lab" => fn -> Color.convert(single, Color.Lab) end,
    "convert: SRGB -> Oklab" => fn -> Color.convert(single, Color.Oklab) end,
    "convert: SRGB -> Oklch" => fn -> Color.convert(single, Color.Oklch) end,
    "convert: SRGB -> JzAzBz" => fn -> Color.convert(single, Color.JzAzBz) end,
    "convert: SRGB -> CAM16UCS" => fn -> Color.convert(single, Color.CAM16UCS) end,
    "convert: Lab -> SRGB (round-trip)" => fn ->
      {:ok, lab} = Color.convert(single, Color.Lab)
      Color.convert(lab, Color.SRGB)
    end,
    "delta_e_2000" => fn ->
      {a, b} = lab_pair
      Color.Distance.delta_e_2000(a, b)
    end,
    "delta_e_76" => fn ->
      {a, b} = lab_pair
      Color.Distance.delta_e_76(a, b)
    end,
    "gamut: in_gamut?(P3 red, :SRGB)" => fn ->
      Color.Gamut.in_gamut?(p3_red, :SRGB)
    end,
    "gamut: to_gamut(P3 red, :SRGB)" => fn ->
      Color.Gamut.to_gamut(p3_red, :SRGB)
    end,
    "Color.new sRGB list" => fn -> Color.new([1.0, 0.5, 0.0]) end,
    "Color.new sRGB int list" => fn -> Color.new([255, 128, 0]) end,
    "Color.new Oklab list" => fn -> Color.new([0.7, 0.1, -0.1], :oklab) end,
    "Color.new hex" => fn -> Color.new("#ff8800") end,
    "Color.new CSS name" => fn -> Color.new("rebeccapurple") end,
    "Color.Mix.mix in Oklab" => fn ->
      Color.Mix.mix("red", "blue", 0.5)
    end,
    "Color.CSS.parse oklch()" => fn ->
      Color.CSS.parse("oklch(70% 0.15 180)")
    end,
    "Color.Contrast.wcag_ratio" => fn ->
      Color.Contrast.wcag_ratio("white", "#777")
    end
  },
  warmup: 0.5,
  time: 1.5,
  print: [fast_warning: false]
)

IO.puts("\n=== Batch (convert_many) vs map(convert) ===\n")

batch = List.duplicate(single, 1000)

Benchee.run(
  %{
    "Enum.map(convert, ..., Color.Lab) x1000" => fn ->
      Enum.map(batch, fn c ->
        {:ok, lab} = Color.convert(c, Color.Lab)
        lab
      end)
    end,
    "convert_many(..., Color.Lab) x1000" => fn ->
      {:ok, list} = Color.convert_many(batch, Color.Lab)
      list
    end,
    "Enum.map(convert, ..., Color.Oklch) x1000" => fn ->
      Enum.map(batch, fn c ->
        {:ok, lch} = Color.convert(c, Color.Oklch)
        lch
      end)
    end,
    "convert_many(..., Color.Oklch) x1000" => fn ->
      {:ok, list} = Color.convert_many(batch, Color.Oklch)
      list
    end
  },
  warmup: 0.5,
  time: 2.0,
  print: [fast_warning: false]
)

IO.puts("\n=== Working-space matrix lookup (cache hit) ===\n")

Benchee.run(
  %{
    "rgb_conversion_matrix(:SRGB)" => fn ->
      Color.RGB.WorkingSpace.rgb_conversion_matrix(:SRGB)
    end,
    "rgb_conversion_matrix(:Rec2020)" => fn ->
      Color.RGB.WorkingSpace.rgb_conversion_matrix(:Rec2020)
    end,
    "rgb_conversion_matrix(:ProPhoto)" => fn ->
      Color.RGB.WorkingSpace.rgb_conversion_matrix(:ProPhoto)
    end
  },
  warmup: 0.2,
  time: 0.8,
  print: [fast_warning: false]
)
