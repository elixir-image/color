# Color

Color is a library to represent and manipulate color information. It is in active development but not yet ready for any use.

The library aims to be a thorough platform for color-aware applications including:
* Color specification in many color spaces
* Correct application of illuminants, observer angles for color temperature
* Correct application of appropriate gamma
* Chromaticity adaptation (necessary when some color spaces like sRGB use a D65 illuminant as standard whereas ICC profiles use D50)
* Color conversion between color space, illuminant, observer angle and gamma
* Conversions to support CSS color definitions (rgb, hsl, hsv)
* Color pallette functions to return analagous, complementary, triadic, tetradic and split complements

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `color` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:color, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/color>.

