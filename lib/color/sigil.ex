defmodule Color.Sigil do
  @moduledoc """
  A sigil for writing color literals in code. Import this module and
  use `~COLOR` to build any supported color.

  > #### Elixir version {: .info}
  >
  > Multi-character sigil names (`~COLOR`) require Elixir 1.15 or
  > later. On older versions this module is not compiled at all —
  > `Code.ensure_loaded?(Color.Sigil)` returns `false` and the hex /
  > CSS / numeric constructors on `Color.SRGB` and the other struct
  > modules are the supported way to build color literals.

  ### Hex / CSS name (no modifier)

      import Color.Sigil

      ~COLOR[#ff0000]
      ~COLOR[#f80]
      ~COLOR[#ff000080]
      ~COLOR[rebeccapurple]

  These all return a `Color.SRGB` struct.

  ### Unit-range sRGB (`r` modifier)

      ~COLOR[1.0, 0.5, 0.0]r

  ### 0..255 sRGB (`b` modifier — for "byte")

      ~COLOR[255, 128, 0]b

  ### CIE Lab (`l` modifier)

      ~COLOR[53.24, 80.09, 67.20]l

  ### Oklab (`o` modifier)

      ~COLOR[0.63, 0.22, 0.13]o

  ### CIE XYZ (`x` modifier)

      ~COLOR[0.4125, 0.2127, 0.0193]x

  ### HSL (`h` modifier)

      ~COLOR[0.5, 1.0, 0.5]h

  ### HSV (`v` modifier)

      ~COLOR[0.5, 1.0, 1.0]v

  ### CMYK (`k` modifier)

      ~COLOR[0.0, 0.5, 1.0, 0.0]k

  All numeric forms accept comma-separated fields. Whitespace around
  the separators is allowed. The parser raises `ArgumentError` if the
  string cannot be interpreted.

  """

  @doc """
  Implements the `~COLOR` sigil.

  See the module doc for the supported modifiers.

  ### Arguments

  * `body` is the string inside the sigil delimiters.

  * `modifiers` is the list of modifier characters after the closing
    delimiter (e.g. `~COLOR[1.0, 0.5, 0.0]r` passes `[?r]`).

  ### Returns

  * The appropriate color struct.

  ### Examples

      iex> import Color.Sigil
      iex> ~COLOR[#ff0000]
      %Color.SRGB{r: 1.0, g: 0.0, b: 0.0, alpha: nil}

      iex> import Color.Sigil
      iex> ~COLOR[red]
      %Color.SRGB{r: 1.0, g: 0.0, b: 0.0, alpha: nil}

      iex> import Color.Sigil
      iex> ~COLOR[1.0, 0.5, 0.0]r
      %Color.SRGB{r: 1.0, g: 0.5, b: 0.0, alpha: nil}

      iex> import Color.Sigil
      iex> ~COLOR[255, 128, 0]b
      %Color.SRGB{r: 1.0, g: 0.5019607843137255, b: 0.0, alpha: nil}

      iex> import Color.Sigil
      iex> ~COLOR[53.24, 80.09, 67.20]l
      %Color.Lab{l: 53.24, a: 80.09, b: 67.2, alpha: nil, illuminant: :D65, observer_angle: 2}

      iex> import Color.Sigil
      iex> ~COLOR[0.63, 0.22, 0.13]o
      %Color.Oklab{l: 0.63, a: 0.22, b: 0.13, alpha: nil}

  """
  defmacro sigil_COLOR({:<<>>, _meta, [body]}, modifiers) when is_binary(body) do
    struct = parse_at_compile_time(body, modifiers)
    Macro.escape(struct)
  end

  # Sigils with interpolation fall through to the runtime path.
  defmacro sigil_COLOR({:<<>>, _meta, _parts} = body, modifiers) do
    quote do
      Color.Sigil.__runtime__(unquote(body), unquote(modifiers))
    end
  end

  @doc false
  def __runtime__(string, modifiers) do
    parse_at_compile_time(string, modifiers)
  end

  defp parse_at_compile_time(body, []) do
    case Color.SRGB.parse(String.trim(body)) do
      {:ok, srgb} -> srgb
      {:error, exception} -> raise exception
    end
  end

  defp parse_at_compile_time(body, ~c"r") do
    [r, g, b] = parse_floats(body, 3)
    %Color.SRGB{r: r, g: g, b: b}
  end

  defp parse_at_compile_time(body, ~c"b") do
    [r, g, b] = parse_floats(body, 3)
    Color.SRGB.unscale255({r, g, b})
  end

  defp parse_at_compile_time(body, ~c"l") do
    [l, a, b] = parse_floats(body, 3)
    %Color.Lab{l: l, a: a, b: b}
  end

  defp parse_at_compile_time(body, ~c"o") do
    [l, a, b] = parse_floats(body, 3)
    %Color.Oklab{l: l, a: a, b: b}
  end

  defp parse_at_compile_time(body, ~c"x") do
    [x, y, z] = parse_floats(body, 3)
    %Color.XYZ{x: x, y: y, z: z, illuminant: :D65, observer_angle: 2}
  end

  defp parse_at_compile_time(body, ~c"h") do
    [h, s, l] = parse_floats(body, 3)
    %Color.HSL{h: h, s: s, l: l}
  end

  defp parse_at_compile_time(body, ~c"v") do
    [h, s, v] = parse_floats(body, 3)
    %Color.HSV{h: h, s: s, v: v}
  end

  defp parse_at_compile_time(body, ~c"k") do
    [c, m, y, k] = parse_floats(body, 4)
    %Color.CMYK{c: c, m: m, y: y, k: k}
  end

  defp parse_at_compile_time(body, modifiers) do
    raise %Color.ParseError{
      function: "~COLOR",
      input: body,
      reason:
        "unknown modifier #{inspect(List.to_string(modifiers))}. " <>
          "Supported: r, b, l, o, x, h, v, k (or none for hex/CSS name)"
    }
  end

  defp parse_floats(body, arity) do
    parts =
      body
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    if length(parts) != arity do
      raise %Color.ParseError{
        function: "~COLOR",
        input: body,
        reason: "expected #{arity} comma-separated values, got #{length(parts)}"
      }
    end

    Enum.map(parts, &parse_number!(&1, body))
  end

  defp parse_number!(s, body) do
    case Float.parse(s) do
      {n, ""} ->
        n

      {n, _rest} ->
        n

      :error ->
        case Integer.parse(s) do
          {n, ""} ->
            n * 1.0

          _ ->
            raise %Color.ParseError{
              function: "~COLOR",
              input: body,
              reason: "invalid number #{inspect(s)}"
            }
        end
    end
  end
end
