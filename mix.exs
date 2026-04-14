defmodule Color.MixProject do
  use Mix.Project

  @version "0.4.0"

  def project do
    [
      app: :color,
      version: @version,
      name: "Color",
      description: description(),
      elixir: "~> 1.17",
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix],
      plt_core_path: "_build/#{Mix.env()}",
      flags: [
        :error_handling,
        :unknown,
        :unmatched_returns,
        :extra_return,
        :missing_return
      ]
    ]
  end

  def description do
    """
    A comprehensive color library: 21 color spaces,
    chromatic adaptation, ICC rendering intents, ΔE2000 / WCAG / APCA
    contrast, gamut mapping, color mixing and gradients, blend modes,
    color harmonies, color temperature, spectral pipeline, and a
    full CSS Color 4 / 5 parser. Zero runtime dependencies.
    """
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      source_url: "https://github.com/elixir-image/color",
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
      "Changelog" => "https://github.com/elixir-image/color/blob/v#{@version}/CHANGELOG.md"
    }
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "logo.jpg",
      extras: [
        "README.md",
        "guides/palettes.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r{guides/.*\.md}
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
        Color.HSL,
        Color.HSLuv,
        Color.HSV,
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
        Color.XyY,
        Color.XYZ,
        Color.YCbCr
      ],
      "CSS Colors": [
        Color.CSS,
        Color.CSSNames,
        Color.CSS.Tokenizer,
        Color.CSS.Calc
      ],
      "Conversion Math": ~r/Color.Conversion/,
      ANSI: [Color.ANSI],
      LED: ~r/Color\.LED/,
      Palettes: ~r/Color\.Palette/,
      ICC: ~r/Color\.ICC/,
      Exceptions: ~r/Color\.[A-Z]\w*Error$/,
      Helpers: [
        Color.Types,
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
      {:ex_doc, "~> 0.32", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:benchee, "~> 1.3", only: [:dev], runtime: false},
      {:stream_data, "~> 1.1", only: [:test], runtime: false}
    ]
  end
end
