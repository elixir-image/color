defmodule Color.CSS do
  @moduledoc """
  CSS Color Module Level 4 parsing and serialisation.

  `parse/1` accepts any of:

  * Hex — `#fff`, `#ffffff`, `#ffff` (RGBA), `#ffffffff` (RRGGBBAA).

  * Named — `red`, `rebeccapurple`, `"Misty Rose"`, `:transparent`.

  * `rgb()` / `rgba()` — `rgb(255 0 0)`, `rgb(255, 0, 0)`,
    `rgb(255 0 0 / 50%)`, `rgba(255 0 0 0.5)`. Both legacy
    comma-separated and modern whitespace forms are accepted.

  * `hsl()` / `hsla()` — `hsl(0 100% 50%)`, `hsl(0deg 100% 50% / .5)`.

  * `hwb()` — `hwb(0 0% 0%)` (CSS Color 4).

  * `lab()` / `lch()` — `lab(50% 40 30)`, `lch(50% 40 30deg)`. The
    lightness accepts `%` or the raw `L` value; `lab` / `lch` use the
    CIE 1976 `L*a*b*` / `LCHab` definitions with a D50 reference
    white as specified by CSS Color 4.

  * `oklab()` / `oklch()` — `oklab(63% 0.2 0.1)`, `oklch(63% 0.2 30)`.

  * `color()` — `color(srgb 1 0 0)`, `color(display-p3 1 0 0)`,
    `color(rec2020 1 0 0)`, `color(prophoto-rgb 1 0 0)`,
    `color(xyz-d65 0.95 1 1.09)`, `color(xyz-d50 ...)`,
    `color(a98-rgb 1 0 0)`, `color(srgb-linear 1 0 0)`.

  `to_css/2` serialises any color struct back to one of these forms.
  The default serialiser choice follows the struct type.

  """

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

  @doc """
  Parses a CSS Color 4 color string.

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

  """
  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      String.starts_with?(trimmed, "#") ->
        Color.SRGB.parse(trimmed)

      matches = Regex.run(~r/^(rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\s*\((.*)\)$/is, trimmed) ->
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

  def to_css(color, options) do
    with {:ok, srgb} <- Color.convert(color, Color.SRGB) do
      to_css(srgb, options)
    else
      _ -> raise ArgumentError, "Cannot serialise #{inspect(color)} to CSS"
    end
  end

  # ---- parse_function ------------------------------------------------------

  defp parse_function(name, args) do
    # Split on either "/" (alpha separator) or only the component
    # separators. CSS accepts both comma and whitespace.
    {components, alpha} = split_alpha(args)
    parts = split_components(components)

    case name do
      "rgb" -> parse_rgb(parts, alpha)
      "rgba" -> parse_rgb(parts, alpha)
      "hsl" -> parse_hsl(parts, alpha)
      "hsla" -> parse_hsl(parts, alpha)
      "hwb" -> parse_hwb(parts, alpha)
      "lab" -> parse_lab(parts, alpha)
      "lch" -> parse_lch(parts, alpha)
      "oklab" -> parse_oklab(parts, alpha)
      "oklch" -> parse_oklch(parts, alpha)
      "color" -> parse_color(parts, alpha)
    end
  end

  defp split_alpha(args) do
    case String.split(args, "/", parts: 2) do
      [components, alpha] -> {String.trim(components), String.trim(alpha)}
      [components] -> {String.trim(components), nil}
    end
  end

  defp split_components(components) do
    components
    |> String.split([",", " ", "\t", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_rgb([r, g, b], alpha) do
    with {:ok, rf} <- parse_rgb_channel(r),
         {:ok, gf} <- parse_rgb_channel(g),
         {:ok, bf} <- parse_rgb_channel(b),
         {:ok, a} <- parse_alpha_opt(alpha) do
      {:ok, %Color.SRGB{r: rf, g: gf, b: bf, alpha: a}}
    end
  end

  # Legacy `rgba(r, g, b, a)` form — four comma-separated values.
  defp parse_rgb([r, g, b, a], nil), do: parse_rgb([r, g, b], a)

  defp parse_rgb(parts, _) do
    {:error, "rgb() expects 3 components, got #{length(parts)}"}
  end

  defp parse_rgb_channel(token) do
    case percent_or_number(token) do
      {:percent, pct} -> {:ok, pct / 100}
      {:number, n} -> {:ok, n / 255}
      :error -> {:error, "Invalid rgb channel #{inspect(token)}"}
    end
  end

  defp parse_hsl([h, s, l], alpha) do
    with {:ok, hf} <- parse_hue(h),
         {:ok, sf} <- parse_percent(s),
         {:ok, lf} <- parse_percent(l),
         {:ok, a} <- parse_alpha_opt(alpha) do
      {:ok, %Color.Hsl{h: hf / 360, s: sf / 100, l: lf / 100, alpha: a}}
    end
  end

  defp parse_hsl([h, s, l, a], nil), do: parse_hsl([h, s, l], a)
  defp parse_hsl(parts, _), do: {:error, "hsl() expects 3 components, got #{length(parts)}"}

  defp parse_hwb([h, w, b], alpha) do
    with {:ok, hf} <- parse_hue(h),
         {:ok, wf} <- parse_percent(w),
         {:ok, bf} <- parse_percent(b),
         {:ok, a} <- parse_alpha_opt(alpha) do
      # HWB -> sRGB per CSS Color 4.
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

  defp parse_hwb(parts, _), do: {:error, "hwb() expects 3 components, got #{length(parts)}"}

  defp parse_lab([l, a, b], alpha) do
    with {:ok, lf} <- parse_percent_or_number(l, 100),
         {:ok, af} <- parse_number(a),
         {:ok, bf} <- parse_number(b),
         {:ok, alpha_val} <- parse_alpha_opt(alpha) do
      # CSS Color 4 lab() uses D50.
      {:ok, %Color.Lab{l: lf, a: af, b: bf, alpha: alpha_val, illuminant: :D50}}
    end
  end

  defp parse_lab(parts, _), do: {:error, "lab() expects 3 components, got #{length(parts)}"}

  defp parse_lch([l, c, h], alpha) do
    with {:ok, lf} <- parse_percent_or_number(l, 100),
         {:ok, cf} <- parse_number(c),
         {:ok, hf} <- parse_hue(h),
         {:ok, alpha_val} <- parse_alpha_opt(alpha) do
      {:ok, %Color.LCHab{l: lf, c: cf, h: hf, alpha: alpha_val, illuminant: :D50}}
    end
  end

  defp parse_lch(parts, _), do: {:error, "lch() expects 3 components, got #{length(parts)}"}

  defp parse_oklab([l, a, b], alpha) do
    with {:ok, lf} <- parse_percent_or_number(l, 1),
         {:ok, af} <- parse_number(a),
         {:ok, bf} <- parse_number(b),
         {:ok, alpha_val} <- parse_alpha_opt(alpha) do
      {:ok, %Color.Oklab{l: lf, a: af, b: bf, alpha: alpha_val}}
    end
  end

  defp parse_oklab(parts, _), do: {:error, "oklab() expects 3 components, got #{length(parts)}"}

  defp parse_oklch([l, c, h], alpha) do
    with {:ok, lf} <- parse_percent_or_number(l, 1),
         {:ok, cf} <- parse_number(c),
         {:ok, hf} <- parse_hue(h),
         {:ok, alpha_val} <- parse_alpha_opt(alpha) do
      {:ok, %Color.Oklch{l: lf, c: cf, h: hf, alpha: alpha_val}}
    end
  end

  defp parse_oklch(parts, _), do: {:error, "oklch() expects 3 components, got #{length(parts)}"}

  defp parse_color([space | rest], alpha) do
    space = String.downcase(space)

    cond do
      Map.has_key?(@working_spaces, space) ->
        parse_color_rgb(space, rest, alpha)

      Map.has_key?(@xyz_spaces, space) ->
        parse_color_xyz(space, rest, alpha)

      true ->
        {:error, "Unknown color() space #{inspect(space)}"}
    end
  end

  defp parse_color([], _), do: {:error, "color() expects a color space and 3 values"}

  defp parse_color_rgb(space, [r, g, b], alpha) do
    with {:ok, rf} <- parse_number(r),
         {:ok, gf} <- parse_number(g),
         {:ok, bf} <- parse_number(b),
         {:ok, alpha_val} <- parse_alpha_opt(alpha) do
      {atom, encoding} = Map.fetch!(@working_spaces, space)

      case {atom, encoding} do
        {:SRGB, :srgb} ->
          {:ok, %Color.SRGB{r: rf, g: gf, b: bf, alpha: alpha_val}}

        {:SRGB, :linear} ->
          {:ok, %Color.RGB{r: rf, g: gf, b: bf, alpha: alpha_val, working_space: :SRGB}}

        {:Adobe, :adobe} ->
          {:ok, %Color.AdobeRGB{r: rf, g: gf, b: bf, alpha: alpha_val}}

        {ws, _} ->
          # Everything else is interpreted as linear in that working
          # space and returned as Color.RGB.
          {:ok, %Color.RGB{r: rf, g: gf, b: bf, alpha: alpha_val, working_space: ws}}
      end
    end
  end

  defp parse_color_rgb(_space, parts, _) do
    {:error, "color() expects 3 channel values, got #{length(parts)}"}
  end

  defp parse_color_xyz(space, [x, y, z], alpha) do
    with {:ok, xf} <- parse_number(x),
         {:ok, yf} <- parse_number(y),
         {:ok, zf} <- parse_number(z),
         {:ok, alpha_val} <- parse_alpha_opt(alpha) do
      illuminant = Map.fetch!(@xyz_spaces, space)
      {:ok, %Color.XYZ{x: xf, y: yf, z: zf, alpha: alpha_val, illuminant: illuminant, observer_angle: 2}}
    end
  end

  defp parse_color_xyz(_space, parts, _) do
    {:error, "color() xyz expects 3 values, got #{length(parts)}"}
  end

  # ---- tokens --------------------------------------------------------------

  defp percent_or_number(token) do
    if String.ends_with?(token, "%") do
      case Float.parse(String.trim_trailing(token, "%")) do
        {n, ""} -> {:percent, n}
        _ -> :error
      end
    else
      case Float.parse(token) do
        {n, ""} ->
          {:number, n}

        _ ->
          case Integer.parse(token) do
            {n, ""} -> {:number, n * 1.0}
            _ -> :error
          end
      end
    end
  end

  defp parse_number(token) do
    case percent_or_number(token) do
      {:number, n} -> {:ok, n}
      _ -> {:error, "Invalid number #{inspect(token)}"}
    end
  end

  defp parse_percent(token) do
    case percent_or_number(token) do
      {:percent, n} -> {:ok, n}
      _ -> {:error, "Expected a percentage, got #{inspect(token)}"}
    end
  end

  # Parses `L` as a percent (relative to `ref`) or a bare number.
  defp parse_percent_or_number(token, ref) do
    case percent_or_number(token) do
      {:percent, n} -> {:ok, n / 100 * ref}
      {:number, n} -> {:ok, n}
      _ -> {:error, "Invalid lightness #{inspect(token)}"}
    end
  end

  defp parse_hue(token) do
    {num_part, unit} =
      cond do
        String.ends_with?(token, "deg") -> {String.trim_trailing(token, "deg"), :deg}
        String.ends_with?(token, "rad") -> {String.trim_trailing(token, "rad"), :rad}
        String.ends_with?(token, "grad") -> {String.trim_trailing(token, "grad"), :grad}
        String.ends_with?(token, "turn") -> {String.trim_trailing(token, "turn"), :turn}
        true -> {token, :deg}
      end

    case Float.parse(num_part) do
      {n, ""} -> {:ok, hue_to_deg(n, unit)}
      _ -> {:error, "Invalid hue #{inspect(token)}"}
    end
  end

  defp hue_to_deg(n, :deg), do: n
  defp hue_to_deg(n, :rad), do: n * 180 / :math.pi()
  defp hue_to_deg(n, :grad), do: n * 360 / 400
  defp hue_to_deg(n, :turn), do: n * 360

  defp parse_alpha_opt(nil), do: {:ok, nil}

  defp parse_alpha_opt(token) do
    case percent_or_number(token) do
      {:percent, n} -> {:ok, n / 100}
      {:number, n} -> {:ok, n}
      _ -> {:error, "Invalid alpha #{inspect(token)}"}
    end
  end

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
