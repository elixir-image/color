defmodule Color.CSS do
  @moduledoc """
  CSS Color Module Level 4 / 5 parsing and serialisation.

  `parse/1` accepts any of:

  * Hex — `#fff`, `#ffffff`, `#ffff` (RGBA), `#ffffffff` (RRGGBBAA).

  * Named — `red`, `rebeccapurple`, `"Misty Rose"`, `:transparent`.

  * `rgb()` / `rgba()` — `rgb(255 0 0)`, `rgb(255, 0, 0)`,
    `rgb(255 0 0 / 50%)`, `rgba(255 0 0 0.5)`. Both legacy
    comma-separated and modern whitespace forms are accepted.

  * `hsl()` / `hsla()` — `hsl(0 100% 50%)`, `hsl(0deg 100% 50% / .5)`.

  * `hwb()` — `hwb(0 0% 0%)`.

  * `lab()` / `lch()` — `lab(50% 40 30)`, `lch(50% 40 30deg)`.
    The lightness accepts `%` or the raw `L` value; `lab` / `lch`
    use the CIE 1976 `L*a*b*` / `LCHab` definitions with a D50
    reference white as specified by CSS Color 4.

  * `oklab()` / `oklch()` — `oklab(63% 0.2 0.1)`, `oklch(63% 0.2 30)`.

  * `color()` — `color(srgb 1 0 0)`, `color(display-p3 1 0 0)`,
    `color(rec2020 1 0 0)`, `color(prophoto-rgb 1 0 0)`,
    `color(xyz-d65 0.95 1 1.09)`, `color(xyz-d50 ...)`,
    `color(a98-rgb 1 0 0)`, `color(srgb-linear 1 0 0)`.

  * `device-cmyk()` *(CSS Color 5)* — `device-cmyk(0% 100% 100% 0%)`,
    `device-cmyk(0 1 1 0 / 50%)`. Returns a `Color.CMYK` struct.

  * `color-mix()` *(CSS Color 5)* —
    `color-mix(in oklch, red 40%, blue)`,
    `color-mix(in lab, red, blue 30%)`. The first argument is
    `in <space>` (any space `Color.Mix.mix/4` understands); the
    remaining two are colors with optional percentages. The mixed
    result is returned in the interpolation space.

  * Relative color syntax *(CSS Color 5)* — `rgb(from <color> r g b)`,
    `oklch(from <color> l c calc(h + 30))`, etc. Inside the function
    body the source color's components are bound to identifiers
    (`r`/`g`/`b` for `rgb()`, `h`/`s`/`l` for `hsl()`, `l`/`c`/`h` for
    LCH-style spaces, etc) and `alpha` is always available. Components
    may be referenced bare or wrapped in `calc()`.

  * `none` keyword *(CSS Color 4)* — `rgb(none 0 0)`,
    `oklch(0.7 none 30)`. A channel of `none` is treated as the
    space's neutral default (zero in the relevant unit).

  * `calc()` — `rgb(calc(255 / 2) 0 0)`,
    `lab(calc(50 + 10) 0 0)`. Inside relative-color syntax, calc()
    expressions can reference the captured component identifiers,
    e.g. `oklch(from teal calc(l + 0.1) c h)`.

  `to_css/2` serialises any color struct back to one of these forms.
  The default serialiser choice follows the struct type.

  """

  alias Color.CSS.{Calc, Tokenizer}
  alias Color.ParseError

  @compile {:inline, parse_error: 1, parse_error: 2}
  defp parse_error(reason), do: %ParseError{reason: reason}
  defp parse_error(function, reason), do: %ParseError{function: function, reason: reason}

  @working_spaces %{
    "srgb" => {:SRGB, :srgb},
    "srgb-linear" => {:SRGB, :linear},
    "display-p3" => {:P3_D65, :srgb},
    "a98-rgb" => {:Adobe, :adobe},
    "prophoto-rgb" => {:ProPhoto, :gamma_1_8},
    "rec2020" => {:Rec2020, :rec2020}
  }

  @xyz_spaces %{
    "xyz" => :D65,
    "xyz-d65" => :D65,
    "xyz-d50" => :D50
  }

  # Maps the CSS color-mix interpolation-space keyword to the
  # `Color.*` struct module that Color.Mix understands.
  @mix_spaces %{
    "srgb" => Color.SRGB,
    "srgb-linear" => Color.SRGB,
    "lab" => Color.Lab,
    "oklab" => Color.Oklab,
    "lch" => Color.LCHab,
    "oklch" => Color.Oklch,
    "hsl" => Color.Hsl,
    "hwb" => Color.SRGB,
    "xyz" => Color.XYZ,
    "xyz-d50" => Color.XYZ,
    "xyz-d65" => Color.XYZ
  }

  @doc """
  Parses a CSS Color 4 / 5 color string.

  ### Arguments

  * `input` is a string.

  ### Returns

  * `{:ok, struct}` on success.

  * `{:error, reason}` otherwise.

  ### Examples

      iex> {:ok, c} = Color.CSS.parse("rgb(255 0 0)")
      iex> {c.r, c.g, c.b}
      {1.0, 0.0, 0.0}

      iex> {:ok, c} = Color.CSS.parse("rgb(255 0 0 / 50%)")
      iex> c.alpha
      0.5

      iex> {:ok, c} = Color.CSS.parse("hsl(120 100% 50%)")
      iex> c.h
      0.3333333333333333

      iex> {:ok, c} = Color.CSS.parse("lab(50% 40 30)")
      iex> {c.l, c.a, c.b}
      {50.0, 40.0, 30.0}

      iex> {:ok, c} = Color.CSS.parse("oklch(63% 0.2 30)")
      iex> {Float.round(c.l, 2), Float.round(c.c, 2), Float.round(c.h, 2)}
      {0.63, 0.2, 30.0}

      iex> {:ok, c} = Color.CSS.parse("color(display-p3 1 0 0)")
      iex> c.working_space
      :P3_D65

      iex> {:ok, c} = Color.CSS.parse("rgb(none 0 0)")
      iex> {c.r, c.g, c.b}
      {0.0, 0.0, 0.0}

      iex> {:ok, c} = Color.CSS.parse("rgb(calc(255 / 2) 0 0)")
      iex> Float.round(c.r, 4)
      0.5

      iex> {:ok, c} = Color.CSS.parse("device-cmyk(0% 100% 100% 0%)")
      iex> {c.c, c.m, c.y, c.k}
      {0.0, 1.0, 1.0, 0.0}

      iex> {:ok, c} = Color.CSS.parse("color-mix(in oklab, red, blue)")
      iex> c.__struct__
      Color.Oklab

      iex> {:ok, c} = Color.CSS.parse("oklch(from red calc(l + 0.1) c h)")
      iex> c.__struct__
      Color.Oklch

  """
  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      String.starts_with?(trimmed, "#") ->
        Color.SRGB.parse(trimmed)

      matches =
          Regex.run(
            ~r/^(rgba?|hsla?|hwb|lab|lch|oklab|oklch|color-mix|color|device-cmyk)\s*\((.*)\)\s*$/is,
            trimmed
          ) ->
        [_, function, args] = matches
        parse_function(String.downcase(function), args)

      true ->
        Color.SRGB.parse(trimmed)
    end
  end

  @doc """
  Serialises a color struct as a CSS Color 4 function string.

  ### Arguments

  * `color` is any supported color struct.

  * `options` is a keyword list.

  ### Options

  * `:as` — override the default serialiser form. One of `:rgb`,
    `:hex`, `:hsl`, `:lab`, `:lch`, `:oklab`, `:oklch`, `:color`.

  ### Returns

  * A string.

  ### Examples

      iex> Color.CSS.to_css(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0})
      "rgb(255 0 0)"

      iex> Color.CSS.to_css(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0, alpha: 0.5})
      "rgb(255 0 0 / 0.5)"

      iex> Color.CSS.to_css(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0}, as: :hex)
      "#ff0000"

      iex> Color.CSS.to_css(%Color.Oklch{l: 0.63, c: 0.2, h: 30.0})
      "oklch(63% 0.2 30)"

      iex> Color.CSS.to_css(%Color.Lab{l: 50.0, a: 40.0, b: 30.0})
      "lab(50% 40 30)"

      iex> Color.CSS.to_css(%Color.CMYK{c: 0.0, m: 1.0, y: 1.0, k: 0.0})
      "device-cmyk(0% 100% 100% 0%)"

  """
  def to_css(color, options \\ [])

  def to_css(%Color.SRGB{} = c, options) do
    case Keyword.get(options, :as, :rgb) do
      :rgb -> srgb_rgb(c)
      :hex -> Color.SRGB.to_hex(c)
      :color -> "color(srgb #{trim(c.r)} #{trim(c.g)} #{trim(c.b)}#{alpha_part(c.alpha)})"
      other -> raise ArgumentError, "Unsupported :as #{inspect(other)} for SRGB"
    end
  end

  def to_css(%Color.Hsl{} = c, _options) do
    "hsl(#{trim(c.h * 360)} #{trim(c.s * 100)}% #{trim(c.l * 100)}%#{alpha_part(c.alpha)})"
  end

  def to_css(%Color.Lab{} = c, _options) do
    "lab(#{trim(c.l)}% #{trim(c.a)} #{trim(c.b)}#{alpha_part(c.alpha)})"
  end

  def to_css(%Color.LCHab{} = c, _options) do
    "lch(#{trim(c.l)}% #{trim(c.c)} #{trim(c.h)}#{alpha_part(c.alpha)})"
  end

  def to_css(%Color.Oklab{} = c, _options) do
    "oklab(#{trim(c.l * 100)}% #{trim(c.a)} #{trim(c.b)}#{alpha_part(c.alpha)})"
  end

  def to_css(%Color.Oklch{} = c, _options) do
    "oklch(#{trim(c.l * 100)}% #{trim(c.c)} #{trim(c.h)}#{alpha_part(c.alpha)})"
  end

  def to_css(%Color.XYZ{} = c, _options) do
    space =
      case c.illuminant do
        :D50 -> "xyz-d50"
        _ -> "xyz-d65"
      end

    "color(#{space} #{trim(c.x)} #{trim(c.y)} #{trim(c.z)}#{alpha_part(c.alpha)})"
  end

  def to_css(%Color.AdobeRGB{} = c, _options) do
    "color(a98-rgb #{trim(c.r)} #{trim(c.g)} #{trim(c.b)}#{alpha_part(c.alpha)})"
  end

  def to_css(%Color.RGB{} = c, _options) do
    space =
      @working_spaces
      |> Enum.find(fn {_css, {atom, _}} -> atom == c.working_space end)
      |> case do
        {name, _} -> name
        nil -> "srgb-linear"
      end

    "color(#{space} #{trim(c.r)} #{trim(c.g)} #{trim(c.b)}#{alpha_part(c.alpha)})"
  end

  def to_css(%Color.CMYK{} = c, _options) do
    "device-cmyk(#{trim(c.c * 100)}% #{trim(c.m * 100)}% #{trim(c.y * 100)}% #{trim(c.k * 100)}%#{alpha_part(c.alpha)})"
  end

  def to_css(color, options) do
    with {:ok, srgb} <- Color.convert(color, Color.SRGB) do
      to_css(srgb, options)
    else
      _ -> raise ArgumentError, "Cannot serialise #{inspect(color)} to CSS"
    end
  end

  # ---- parse_function ------------------------------------------------------

  defp parse_function("color-mix", args), do: parse_color_mix(args)
  defp parse_function("device-cmyk", args), do: parse_device_cmyk(args)

  defp parse_function(name, args) do
    # Tokenize the arg list, then split off `from <color>` (relative
    # color syntax) before splitting alpha.
    with {:ok, tokens} <- Tokenizer.tokenize(args),
         {:ok, bindings, tokens} <- maybe_extract_from(name, tokens),
         {:ok, components, alpha} <- split_alpha(tokens) do
      case name do
        "rgb" -> parse_rgb(components, alpha, bindings)
        "rgba" -> parse_rgb(components, alpha, bindings)
        "hsl" -> parse_hsl(components, alpha, bindings)
        "hsla" -> parse_hsl(components, alpha, bindings)
        "hwb" -> parse_hwb(components, alpha, bindings)
        "lab" -> parse_lab(components, alpha, bindings)
        "lch" -> parse_lch(components, alpha, bindings)
        "oklab" -> parse_oklab(components, alpha, bindings)
        "oklch" -> parse_oklch(components, alpha, bindings)
        "color" -> parse_color(components, alpha, bindings)
      end
    end
  end

  # ---- relative color syntax ----------------------------------------------

  # Source-color component bindings live in a small map keyed by the
  # identifier the spec assigns for each color function. The map also
  # carries `"alpha"` so `alpha` can be referenced inside calc().
  defp maybe_extract_from(name, tokens) do
    case tokens do
      [{:ident, "from"} | rest] ->
        # Pull tokens until we have a complete color expression. The
        # tokenizer already grouped function calls into a single token
        # so the source color is at most a single token (struct call,
        # named color, hex, ...) — but the named-color form may span
        # multiple identifier tokens too. We re-stringify the rest,
        # parse the leading color greedily, then re-tokenize what's
        # left.
        case extract_source_color(rest) do
          {:ok, color, remaining_tokens} ->
            case bindings_for(name, color) do
              {:ok, bindings} -> {:ok, bindings, remaining_tokens}
              {:error, _} = err -> err
            end

          {:error, _} = err ->
            err
        end

      _ ->
        {:ok, nil, tokens}
    end
  end

  # The source color is the next token (a function call, hex, or
  # named color). For multi-word names like `"misty rose"` the
  # tokenizer would split them, but CSS Color 5 only allows a single
  # <color> production here, and the spec's grammar treats it as one
  # token, so we accept exactly one.
  defp extract_source_color([token | rest]) do
    text = stringify_token(token)

    case parse(text) do
      {:ok, color} -> {:ok, color, rest}
      {:error, _} = err -> err
    end
  end

  defp extract_source_color([]) do
    {:error, parse_error("Relative color syntax: missing source color after `from`")}
  end

  defp stringify_token({:ident, s}), do: s
  defp stringify_token({:number, n}), do: to_string(n)
  defp stringify_token({:percent, p}), do: "#{p}%"
  defp stringify_token({:hex, s}), do: "#" <> s
  defp stringify_token({:func, name, body}), do: "#{name}(#{body})"
  defp stringify_token({:slash}), do: "/"

  # Build a binding map from a parsed source color, converted to the
  # space named by the *target* function.
  defp bindings_for("rgb", color), do: rgb_bindings(color)
  defp bindings_for("rgba", color), do: rgb_bindings(color)
  defp bindings_for("hsl", color), do: hsl_bindings(color)
  defp bindings_for("hsla", color), do: hsl_bindings(color)
  defp bindings_for("hwb", color), do: hwb_bindings(color)
  defp bindings_for("lab", color), do: lab_bindings(color, Color.Lab)
  defp bindings_for("lch", color), do: lch_bindings(color, Color.LCHab)
  defp bindings_for("oklab", color), do: lab_bindings(color, Color.Oklab)
  defp bindings_for("oklch", color), do: lch_bindings(color, Color.Oklch)
  defp bindings_for("color", color), do: rgb_bindings(color)

  defp rgb_bindings(color) do
    with {:ok, %Color.SRGB{r: r, g: g, b: b, alpha: a}} <- Color.convert(color, Color.SRGB) do
      {:ok, %{"r" => r * 255, "g" => g * 255, "b" => b * 255, "alpha" => a || 1.0}}
    end
  end

  defp hsl_bindings(color) do
    with {:ok, %Color.Hsl{h: h, s: s, l: l, alpha: a}} <- Color.convert(color, Color.Hsl) do
      {:ok, %{"h" => h * 360, "s" => s * 100, "l" => l * 100, "alpha" => a || 1.0}}
    end
  end

  defp hwb_bindings(color) do
    # CSS HWB derives whiteness/blackness from HSV: w = (1 - s) * v,
    # b = 1 - v. We use HSV directly since the library exposes it.
    with {:ok, %Color.Hsv{h: h, s: s, v: v, alpha: a}} <- Color.convert(color, Color.Hsv) do
      w = (1 - s) * v
      bk = 1 - v
      {:ok, %{"h" => h * 360, "w" => w * 100, "b" => bk * 100, "alpha" => a || 1.0}}
    end
  end

  defp lab_bindings(color, Color.Lab) do
    with {:ok, %Color.Lab{l: l, a: a, b: b, alpha: alpha}} <- Color.convert(color, Color.Lab) do
      {:ok, %{"l" => l, "a" => a, "b" => b, "alpha" => alpha || 1.0}}
    end
  end

  defp lab_bindings(color, Color.Oklab) do
    with {:ok, %Color.Oklab{l: l, a: a, b: b, alpha: alpha}} <- Color.convert(color, Color.Oklab) do
      {:ok, %{"l" => l, "a" => a, "b" => b, "alpha" => alpha || 1.0}}
    end
  end

  defp lch_bindings(color, Color.LCHab) do
    with {:ok, %Color.LCHab{l: l, c: c, h: h, alpha: alpha}} <- Color.convert(color, Color.LCHab) do
      {:ok, %{"l" => l, "c" => c, "h" => h, "alpha" => alpha || 1.0}}
    end
  end

  defp lch_bindings(color, Color.Oklch) do
    with {:ok, %Color.Oklch{l: l, c: c, h: h, alpha: alpha}} <- Color.convert(color, Color.Oklch) do
      {:ok, %{"l" => l, "c" => c, "h" => h, "alpha" => alpha || 1.0}}
    end
  end

  # ---- alpha + component splitting ----------------------------------------

  # Split a token list into `{components, alpha}` pairs. Alpha is
  # introduced either by a `/` token (modern syntax) or by a fourth
  # comma-separated value (legacy rgba/hsla form, handled by the
  # individual parsers below).
  defp split_alpha(tokens) do
    case Enum.find_index(tokens, &match?({:slash}, &1)) do
      nil ->
        {:ok, tokens, nil}

      idx ->
        {components, [_slash | rest]} = Enum.split(tokens, idx)

        case rest do
          [alpha_token] -> {:ok, components, alpha_token}
          _ -> {:error, parse_error("Expected a single alpha value after `/`")}
        end
    end
  end

  # ---- rgb / rgba ----------------------------------------------------------

  defp parse_rgb([r, g, b], alpha, bindings) do
    with {:ok, rf} <- resolve_rgb_channel(r, bindings),
         {:ok, gf} <- resolve_rgb_channel(g, bindings),
         {:ok, bf} <- resolve_rgb_channel(b, bindings),
         {:ok, a} <- resolve_alpha(alpha, bindings) do
      {:ok, %Color.SRGB{r: rf, g: gf, b: bf, alpha: a}}
    end
  end

  defp parse_rgb([r, g, b, a], nil, bindings), do: parse_rgb([r, g, b], a, bindings)

  defp parse_rgb(parts, _, _) do
    {:error, parse_error("rgb", "expects 3 components, got #{length(parts)}")}
  end

  defp resolve_rgb_channel(:none, _), do: {:ok, 0.0}

  defp resolve_rgb_channel(token, bindings) do
    case eval_component(token, bindings, 255) do
      {:ok, {:number, n}} -> {:ok, n / 255}
      {:ok, {:percent, p}} -> {:ok, p / 100}
      {:error, _} = err -> err
    end
  end

  # ---- hsl / hsla ---------------------------------------------------------

  defp parse_hsl([h, s, l], alpha, bindings) do
    with {:ok, hf} <- resolve_hue(h, bindings),
         {:ok, sf} <- resolve_percent(s, bindings, "HSL saturation"),
         {:ok, lf} <- resolve_percent(l, bindings, "HSL lightness"),
         {:ok, a} <- resolve_alpha(alpha, bindings) do
      {:ok, %Color.Hsl{h: hf / 360, s: sf / 100, l: lf / 100, alpha: a}}
    end
  end

  defp parse_hsl([h, s, l, a], nil, bindings), do: parse_hsl([h, s, l], a, bindings)
  defp parse_hsl(parts, _, _),
    do: {:error, parse_error("hsl", "expects 3 components, got #{length(parts)}")}

  # ---- hwb -----------------------------------------------------------------

  defp parse_hwb([h, w, b], alpha, bindings) do
    with {:ok, hf} <- resolve_hue(h, bindings),
         {:ok, wf} <- resolve_percent(w, bindings, "HWB whiteness"),
         {:ok, bf} <- resolve_percent(b, bindings, "HWB blackness"),
         {:ok, a} <- resolve_alpha(alpha, bindings) do
      wf = wf / 100
      bf = bf / 100

      if wf + bf >= 1 do
        grey = wf / (wf + bf)
        {:ok, %Color.SRGB{r: grey, g: grey, b: grey, alpha: a}}
      else
        {:ok, hsl} = Color.Hsl.to_srgb(%Color.Hsl{h: hf / 360, s: 1.0, l: 0.5})
        r = hsl.r * (1 - wf - bf) + wf
        g = hsl.g * (1 - wf - bf) + wf
        b = hsl.b * (1 - wf - bf) + wf
        {:ok, %Color.SRGB{r: r, g: g, b: b, alpha: a}}
      end
    end
  end

  defp parse_hwb(parts, _, _),
    do: {:error, parse_error("hwb", "expects 3 components, got #{length(parts)}")}

  # ---- lab / lch -----------------------------------------------------------

  defp parse_lab([l, a, b], alpha, bindings) do
    with {:ok, lf} <- resolve_percent_or_number(l, bindings, 100),
         {:ok, af} <- resolve_number(a, bindings),
         {:ok, bf} <- resolve_number(b, bindings),
         {:ok, alpha_val} <- resolve_alpha(alpha, bindings) do
      {:ok, %Color.Lab{l: lf, a: af, b: bf, alpha: alpha_val, illuminant: :D50}}
    end
  end

  defp parse_lab(parts, _, _),
    do: {:error, parse_error("lab", "expects 3 components, got #{length(parts)}")}

  defp parse_lch([l, c, h], alpha, bindings) do
    with {:ok, lf} <- resolve_percent_or_number(l, bindings, 100),
         {:ok, cf} <- resolve_number(c, bindings),
         {:ok, hf} <- resolve_hue(h, bindings),
         {:ok, alpha_val} <- resolve_alpha(alpha, bindings) do
      {:ok, %Color.LCHab{l: lf, c: cf, h: hf, alpha: alpha_val, illuminant: :D50}}
    end
  end

  defp parse_lch(parts, _, _),
    do: {:error, parse_error("lch", "expects 3 components, got #{length(parts)}")}

  # ---- oklab / oklch -------------------------------------------------------

  defp parse_oklab([l, a, b], alpha, bindings) do
    with {:ok, lf} <- resolve_percent_or_number(l, bindings, 1),
         {:ok, af} <- resolve_number(a, bindings),
         {:ok, bf} <- resolve_number(b, bindings),
         {:ok, alpha_val} <- resolve_alpha(alpha, bindings) do
      {:ok, %Color.Oklab{l: lf, a: af, b: bf, alpha: alpha_val}}
    end
  end

  defp parse_oklab(parts, _, _),
    do: {:error, parse_error("oklab", "expects 3 components, got #{length(parts)}")}

  defp parse_oklch([l, c, h], alpha, bindings) do
    with {:ok, lf} <- resolve_percent_or_number(l, bindings, 1),
         {:ok, cf} <- resolve_number(c, bindings),
         {:ok, hf} <- resolve_hue(h, bindings),
         {:ok, alpha_val} <- resolve_alpha(alpha, bindings) do
      {:ok, %Color.Oklch{l: lf, c: cf, h: hf, alpha: alpha_val}}
    end
  end

  defp parse_oklch(parts, _, _),
    do: {:error, parse_error("oklch", "expects 3 components, got #{length(parts)}")}

  # ---- color() -------------------------------------------------------------

  defp parse_color([{:ident, space} | rest], alpha, bindings) do
    space = String.downcase(space)

    cond do
      Map.has_key?(@working_spaces, space) ->
        parse_color_rgb(space, rest, alpha, bindings)

      Map.has_key?(@xyz_spaces, space) ->
        parse_color_xyz(space, rest, alpha, bindings)

      true ->
        {:error, parse_error("color", "unknown space #{inspect(space)}")}
    end
  end

  defp parse_color([], _, _),
    do: {:error, parse_error("color", "expects a color space and 3 values")}

  defp parse_color(_, _, _),
    do: {:error, parse_error("color", "expects a color space identifier first")}

  defp parse_color_rgb(space, [r, g, b], alpha, bindings) do
    with {:ok, rf} <- resolve_number(r, bindings),
         {:ok, gf} <- resolve_number(g, bindings),
         {:ok, bf} <- resolve_number(b, bindings),
         {:ok, alpha_val} <- resolve_alpha(alpha, bindings) do
      {atom, encoding} = Map.fetch!(@working_spaces, space)

      case {atom, encoding} do
        {:SRGB, :srgb} ->
          {:ok, %Color.SRGB{r: rf, g: gf, b: bf, alpha: alpha_val}}

        {:SRGB, :linear} ->
          {:ok, %Color.RGB{r: rf, g: gf, b: bf, alpha: alpha_val, working_space: :SRGB}}

        {:Adobe, :adobe} ->
          {:ok, %Color.AdobeRGB{r: rf, g: gf, b: bf, alpha: alpha_val}}

        {ws, _} ->
          {:ok, %Color.RGB{r: rf, g: gf, b: bf, alpha: alpha_val, working_space: ws}}
      end
    end
  end

  defp parse_color_rgb(_space, parts, _, _) do
    {:error, parse_error("color", "expects 3 channel values, got #{length(parts)}")}
  end

  defp parse_color_xyz(space, [x, y, z], alpha, bindings) do
    with {:ok, xf} <- resolve_number(x, bindings),
         {:ok, yf} <- resolve_number(y, bindings),
         {:ok, zf} <- resolve_number(z, bindings),
         {:ok, alpha_val} <- resolve_alpha(alpha, bindings) do
      illuminant = Map.fetch!(@xyz_spaces, space)

      {:ok,
       %Color.XYZ{
         x: xf,
         y: yf,
         z: zf,
         alpha: alpha_val,
         illuminant: illuminant,
         observer_angle: 2
       }}
    end
  end

  defp parse_color_xyz(_space, parts, _, _) do
    {:error, parse_error("color", "xyz expects 3 values, got #{length(parts)}")}
  end

  # ---- device-cmyk() -------------------------------------------------------

  defp parse_device_cmyk(args) do
    with {:ok, tokens} <- Tokenizer.tokenize(args),
         {:ok, components, alpha} <- split_alpha(tokens) do
      case components do
        [c, m, y, k] ->
          with {:ok, cf} <- resolve_unit(c, nil, "device-cmyk channel"),
               {:ok, mf} <- resolve_unit(m, nil, "device-cmyk channel"),
               {:ok, yf} <- resolve_unit(y, nil, "device-cmyk channel"),
               {:ok, kf} <- resolve_unit(k, nil, "device-cmyk channel"),
               {:ok, alpha_val} <- resolve_alpha(alpha, nil) do
            {:ok, %Color.CMYK{c: cf, m: mf, y: yf, k: kf, alpha: alpha_val}}
          end

        _ ->
          {:error,
           parse_error("device-cmyk", "expects 4 components, got #{length(components)}")}
      end
    end
  end

  # ---- color-mix() --------------------------------------------------------

  # color-mix(in <space> [<hue-mode>], <color> [<percent>], <color> [<percent>])
  defp parse_color_mix(args) do
    with {:ok, segments} <- split_top_level_commas(args) do
      case segments do
        [method, c1, c2] ->
          with {:ok, {space_module, hue_mode}} <- parse_mix_method(method),
               {:ok, color1, p1} <- parse_mix_color(c1),
               {:ok, color2, p2} <- parse_mix_color(c2) do
            do_color_mix(space_module, hue_mode, color1, p1, color2, p2)
          end

        _ ->
          {:error,
           parse_error(
             "color-mix",
             "expects 3 comma-separated arguments (method, color, color); got #{length(segments)}"
           )}
      end
    end
  end

  defp parse_mix_method(text) do
    with {:ok, tokens} <- Tokenizer.tokenize(text) do
      case tokens do
        [{:ident, "in"}, {:ident, space} | rest] ->
          space = String.downcase(space)

          case Map.fetch(@mix_spaces, space) do
            {:ok, module} ->
              hue_mode = parse_hue_mode(rest)
              {:ok, {module, hue_mode}}

            :error ->
              {:error,
               parse_error("color-mix", "unknown interpolation space #{inspect(space)}")}
          end

        _ ->
          {:error, parse_error("color-mix", "first argument must be `in <space>`")}
      end
    end
  end

  defp parse_hue_mode([]), do: :shorter
  defp parse_hue_mode([{:ident, "shorter"}, {:ident, "hue"}]), do: :shorter
  defp parse_hue_mode([{:ident, "longer"}, {:ident, "hue"}]), do: :longer
  defp parse_hue_mode([{:ident, "increasing"}, {:ident, "hue"}]), do: :increasing
  defp parse_hue_mode([{:ident, "decreasing"}, {:ident, "hue"}]), do: :decreasing
  defp parse_hue_mode(_), do: :shorter

  defp parse_mix_color(text) do
    with {:ok, tokens} <- Tokenizer.tokenize(text) do
      # The percentage, if present, is the LAST token (a {:percent, n}).
      case List.last(tokens) do
        {:percent, p} ->
          rest = Enum.drop(tokens, -1)
          color_text = rest |> Enum.map(&stringify_token/1) |> Enum.join(" ")

          with {:ok, color} <- parse(color_text) do
            {:ok, color, p / 100}
          end

        _ ->
          color_text = tokens |> Enum.map(&stringify_token/1) |> Enum.join(" ")

          with {:ok, color} <- parse(color_text) do
            {:ok, color, nil}
          end
      end
    end
  end

  defp do_color_mix(space, hue_mode, color1, p1, color2, p2) do
    {t, scale} = mix_t(p1, p2)

    with {:ok, ca} <- Color.convert(color1, space),
         {:ok, cb} <- Color.convert(color2, space) do
      mixed = lerp_struct(space, ca, cb, t, hue_mode)

      mixed =
        case scale do
          1.0 -> mixed
          s -> scale_alpha(mixed, s)
        end

      {:ok, mixed}
    end
  end

  # CSS Color 5 percentage normalisation:
  # * If both percentages are missing, t = 0.5, scale = 1.0.
  # * If only one is given (p1), t = 1 - p1, scale = 1.0.
  # * If both are given and they sum to 100%, t = p2.
  # * If both are given and they don't sum to 100%, t = p2 / (p1 + p2)
  #   and the result alpha is multiplied by (p1 + p2).
  defp mix_t(nil, nil), do: {0.5, 1.0}
  defp mix_t(p1, nil), do: {1.0 - p1, 1.0}
  defp mix_t(nil, p2), do: {p2, 1.0}

  defp mix_t(p1, p2) do
    sum = p1 + p2

    cond do
      sum == 0 -> {0.5, 0.0}
      abs(sum - 1.0) < 1.0e-9 -> {p2, 1.0}
      true -> {p2 / sum, sum}
    end
  end

  # We re-implement the inner mix step here (rather than calling
  # Color.Mix.mix/4) so that the result stays in the interpolation
  # space — CSS Color 5 says color-mix() returns a color in the
  # interpolation space, while Color.Mix.mix/4 always converts to SRGB
  # at the end.
  defp lerp_struct(Color.SRGB, a, b, t, _),
    do: %Color.SRGB{
      r: lerp(a.r, b.r, t),
      g: lerp(a.g, b.g, t),
      b: lerp(a.b, b.b, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp lerp_struct(Color.Lab, a, b, t, _),
    do: %Color.Lab{
      l: lerp(a.l, b.l, t),
      a: lerp(a.a, b.a, t),
      b: lerp(a.b, b.b, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t),
      illuminant: a.illuminant,
      observer_angle: a.observer_angle
    }

  defp lerp_struct(Color.Oklab, a, b, t, _),
    do: %Color.Oklab{
      l: lerp(a.l, b.l, t),
      a: lerp(a.a, b.a, t),
      b: lerp(a.b, b.b, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp lerp_struct(Color.Oklch, a, b, t, hue_mode),
    do: %Color.Oklch{
      l: lerp(a.l, b.l, t),
      c: lerp(a.c, b.c, t),
      h: hue_lerp(a.h, b.h, t, hue_mode),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp lerp_struct(Color.LCHab, a, b, t, hue_mode),
    do: %Color.LCHab{
      l: lerp(a.l, b.l, t),
      c: lerp(a.c, b.c, t),
      h: hue_lerp(a.h, b.h, t, hue_mode),
      alpha: lerp_alpha(a.alpha, b.alpha, t),
      illuminant: a.illuminant,
      observer_angle: a.observer_angle
    }

  defp lerp_struct(Color.Hsl, a, b, t, hue_mode),
    do: %Color.Hsl{
      h: hue_lerp(a.h * 360, b.h * 360, t, hue_mode) / 360,
      s: lerp(a.s, b.s, t),
      l: lerp(a.l, b.l, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp lerp_struct(Color.XYZ, a, b, t, _),
    do: %Color.XYZ{
      x: lerp(a.x, b.x, t),
      y: lerp(a.y, b.y, t),
      z: lerp(a.z, b.z, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t),
      illuminant: a.illuminant,
      observer_angle: a.observer_angle
    }

  defp lerp(a, b, t), do: a * (1 - t) + b * t

  defp lerp_alpha(nil, nil, _), do: nil
  defp lerp_alpha(a, nil, t), do: lerp(a || 1.0, 1.0, t)
  defp lerp_alpha(nil, b, t), do: lerp(1.0, b || 1.0, t)
  defp lerp_alpha(a, b, t), do: lerp(a, b, t)

  defp hue_lerp(a, b, t, mode) do
    diff =
      case mode do
        :shorter -> shorter_hue_diff(a, b)
        :longer -> longer_hue_diff(a, b)
        :increasing -> increasing_hue_diff(a, b)
        :decreasing -> decreasing_hue_diff(a, b)
      end

    wrap360(a + diff * t)
  end

  defp shorter_hue_diff(a, b) do
    d = fmod(b - a, 360)

    cond do
      d > 180 -> d - 360
      d < -180 -> d + 360
      true -> d
    end
  end

  defp longer_hue_diff(a, b) do
    d = shorter_hue_diff(a, b)
    if d > 0, do: d - 360, else: d + 360
  end

  defp increasing_hue_diff(a, b) do
    fmod(b - a + 360, 360)
  end

  defp decreasing_hue_diff(a, b) do
    -fmod(a - b + 360, 360)
  end

  defp fmod(a, b) do
    a - b * Float.floor(a / b)
  end

  defp wrap360(h) do
    fmod(h + 360.0 * 1000, 360)
  end

  defp scale_alpha(%{alpha: nil} = c, scale), do: %{c | alpha: scale}
  defp scale_alpha(%{alpha: a} = c, scale), do: %{c | alpha: a * scale}

  # Split a string on top-level commas (paren depth 0). Used by
  # color-mix() to separate its three arguments.
  defp split_top_level_commas(string) do
    {pieces, current, depth} =
      string
      |> String.to_charlist()
      |> Enum.reduce({[], [], 0}, fn
        ?(, {acc, cur, d} -> {acc, [?( | cur], d + 1}
        ?), {acc, cur, d} when d > 0 -> {acc, [?) | cur], d - 1}
        ?,, {acc, cur, 0} -> {[finalize_chunk(cur) | acc], [], 0}
        c, {acc, cur, d} -> {acc, [c | cur], d}
      end)

    if depth != 0 do
      {:error, parse_error("color-mix", "unbalanced parens in arguments")}
    else
      {:ok, Enum.reverse([finalize_chunk(current) | pieces])}
    end
  end

  defp finalize_chunk(chars) do
    chars |> Enum.reverse() |> List.to_string() |> String.trim()
  end

  # ---- token resolution ----------------------------------------------------

  # Each `resolve_*` takes a token and an optional bindings map (for
  # relative color syntax). Returns `{:ok, value}` or `{:error,
  # reason}`.

  # Numeric resolution: produces a bare float.
  defp resolve_number(:none, _bindings), do: {:ok, 0.0}

  defp resolve_number(token, bindings) do
    case eval_component(token, bindings, nil) do
      {:ok, {:number, n}} -> {:ok, n}
      {:ok, {:percent, _}} -> {:error, parse_error("Expected a number, not a percentage")}
      {:error, _} = err -> err
    end
  end

  # Percent resolution: produces the raw percent (e.g. 50.0 for "50%").
  # Accepts:
  #   * `:none`             → 0.0
  #   * `{:percent, p}`     → p
  #   * an identifier bound to a percent-domain number — captured by
  #     `from <color>` for `hsl()` `s`/`l`, `hwb()` `w`/`b` etc., and
  #     stored already in percent units.
  #   * a calc() expression evaluated in the same number domain as
  #     the binding it references.
  defp resolve_percent(:none, _bindings, _label), do: {:ok, 0.0}

  defp resolve_percent({:ident, _} = token, bindings, _label) when not is_nil(bindings) do
    case eval_component(token, bindings, nil) do
      {:ok, {:number, n}} -> {:ok, n}
      {:error, _} = err -> err
    end
  end

  defp resolve_percent({:func, "calc", _} = token, bindings, _label) when not is_nil(bindings) do
    case eval_component(token, bindings, nil) do
      {:ok, {:number, n}} -> {:ok, n}
      {:error, _} = err -> err
    end
  end

  defp resolve_percent(token, bindings, label) do
    case eval_component(token, bindings, nil) do
      {:ok, {:percent, p}} -> {:ok, p}
      _ -> {:error, parse_error("Expected a percentage for #{label}")}
    end
  end

  # Either: percent (scaled to ref) or bare number.
  defp resolve_percent_or_number(:none, _bindings, _ref), do: {:ok, 0.0}

  defp resolve_percent_or_number(token, bindings, ref) do
    case eval_component(token, bindings, nil) do
      {:ok, {:percent, p}} -> {:ok, p / 100 * ref}
      {:ok, {:number, n}} -> {:ok, n}
      {:error, _} = err -> err
    end
  end

  # Unit (0..1) resolution from either a percent or a number in [0,1].
  defp resolve_unit(:none, _, _), do: {:ok, 0.0}

  defp resolve_unit(token, bindings, _label) do
    case eval_component(token, bindings, nil) do
      {:ok, {:percent, p}} -> {:ok, p / 100}
      {:ok, {:number, n}} -> {:ok, n}
      {:error, _} = err -> err
    end
  end

  # Hue resolution: returns degrees in any range; caller does the wrapping.
  defp resolve_hue(:none, _bindings), do: {:ok, 0.0}

  defp resolve_hue({:number, n}, _bindings), do: {:ok, n * 1.0}
  defp resolve_hue({:percent, _}, _), do: {:error, parse_error("Hue cannot be a percentage")}

  defp resolve_hue({:ident, ident}, bindings) do
    case bindings && Map.fetch(bindings, ident) do
      {:ok, value} -> {:ok, value * 1.0}
      _ -> {:error, parse_error("Unknown identifier `#{ident}` in hue position")}
    end
  end

  defp resolve_hue({:func, "calc", body}, bindings) do
    with {:ok, ast} <- Calc.parse(body),
         {:ok, value} <- Calc.evaluate(ast, bindings || %{}) do
      {:ok, value * 1.0}
    end
  end

  defp resolve_hue({:hue, n, unit}, _bindings), do: {:ok, hue_to_deg(n, unit)}
  defp resolve_hue(other, _), do: {:error, parse_error("Invalid hue token #{inspect(other)}")}

  defp resolve_alpha(nil, _bindings), do: {:ok, nil}
  defp resolve_alpha(:none, _), do: {:ok, 0.0}

  defp resolve_alpha({:number, n}, _), do: {:ok, n * 1.0}
  defp resolve_alpha({:percent, p}, _), do: {:ok, p / 100}

  defp resolve_alpha({:ident, "alpha"}, bindings) when not is_nil(bindings) do
    {:ok, Map.fetch!(bindings, "alpha") * 1.0}
  end

  defp resolve_alpha({:ident, ident}, bindings) when not is_nil(bindings) do
    case Map.fetch(bindings, ident) do
      {:ok, v} -> {:ok, v * 1.0}
      :error -> {:error, parse_error("Unknown alpha identifier `#{ident}`")}
    end
  end

  defp resolve_alpha({:func, "calc", body}, bindings) do
    with {:ok, ast} <- Calc.parse(body),
         {:ok, value} <- Calc.evaluate(ast, bindings || %{}) do
      {:ok, value * 1.0}
    end
  end

  defp resolve_alpha(other, _),
    do: {:error, parse_error("Invalid alpha token #{inspect(other)}")}

  # Generic component evaluator: turns a token into either
  # `{:number, n}` or `{:percent, n}`, evaluating calc() and
  # resolving identifier references inside `bindings`.
  #
  # `numeric_scale` is the channel's reference range when an identifier
  # was bound in scaled units (currently used as documentation only).
  defp eval_component({:number, n}, _bindings, _scale), do: {:ok, {:number, n * 1.0}}
  defp eval_component({:percent, p}, _bindings, _scale), do: {:ok, {:percent, p * 1.0}}
  defp eval_component({:hue, n, unit}, _bindings, _scale), do: {:ok, {:number, hue_to_deg(n, unit)}}

  defp eval_component({:ident, ident}, bindings, _scale) when not is_nil(bindings) do
    case Map.fetch(bindings, ident) do
      {:ok, value} -> {:ok, {:number, value * 1.0}}
      :error -> {:error, parse_error("Unknown identifier `#{ident}` in component position")}
    end
  end

  defp eval_component({:ident, ident}, _bindings, _scale) do
    {:error,
     parse_error("Bare identifier `#{ident}` is only valid inside relative color syntax")}
  end

  defp eval_component({:func, "calc", body}, bindings, _scale) do
    with {:ok, ast} <- Calc.parse(body),
         {:ok, value} <- Calc.evaluate(ast, bindings || %{}) do
      {:ok, {:number, value * 1.0}}
    end
  end

  defp eval_component(other, _, _),
    do: {:error, parse_error("Unexpected component token #{inspect(other)}")}

  # ---- legacy hue helpers (used by hue_to_deg in the new path too) ---------

  defp hue_to_deg(n, :deg), do: n * 1.0
  defp hue_to_deg(n, :rad), do: n * 180 / :math.pi()
  defp hue_to_deg(n, :grad), do: n * 360 / 400
  defp hue_to_deg(n, :turn), do: n * 360

  # ---- serialisation helpers -----------------------------------------------

  defp srgb_rgb(%Color.SRGB{r: r, g: g, b: b, alpha: a}) do
    "rgb(#{round_byte(r)} #{round_byte(g)} #{round_byte(b)}#{alpha_part(a)})"
  end

  defp round_byte(v) do
    v
    |> max(0.0)
    |> min(1.0)
    |> Kernel.*(255)
    |> round()
  end

  defp alpha_part(nil), do: ""
  defp alpha_part(1.0), do: ""
  defp alpha_part(a), do: " / #{trim(a)}"

  defp trim(n) when is_integer(n), do: Integer.to_string(n)

  defp trim(n) when is_float(n) do
    rounded = Float.round(n, 4)

    if rounded == trunc(rounded) do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, [:compact, decimals: 4])
    end
  end
end
