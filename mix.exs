defmodule Color.MixProject do
  use Mix.Project

  @version "0.1.0"
  def project do
    [
      app: :color,
      version: @version,
      name: "Color",
      description: description(),
      elixir: "~> 1.17",
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def description do
    "Color definition, conversion and calculation"
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE.md"
      ]
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/elixir-image/color",
      "Readme" => "https://github.com/elixir-image/color/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/elixir-image/color/blob/v#{@version}/CHANGELOG.md",
    }
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "logo.jpg",
      extras: [
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ],
      formatters: ["html", "markdown"],
      groups_for_modules: groups_for_modules(),
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  def groups_for_modules do
    [
      "Color Spaces": [
        Color.AdobeRGB,
        Color.CAM16UCS,
        Color.CMYK,
        Color.HPLuv,
        Color.Hsl,
        Color.HSLuv,
        Color.Hsv,
        Color.ICtCp,
        Color.IPT,
        Color.JzAzBz,
        Color.Lab,
        Color.LCHab,
        Color.LCHuv,
        Color.Luv,
        Color.Oklab,
        Color.Oklch,
        Color.RGB,
        Color.SRGB,
        Color.XYY,
        Color.XYZ,
        Color.YCbCr
      ],
      "CSS Colors": [Color.CSS, Color.CSSNames],
      "Conversion Math": ~r/Color.Conversion/,
      "Helpers": [
        Color.HSLuv.Gamut,
        Color.RGB.WorkingSpace,
        Color.Spectral.Tables
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.32", only: [:dev]}
    ]
  end
end
