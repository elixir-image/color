defmodule Color.ANSI do
  @moduledoc """
  ANSI SGR (Select Graphic Rendition) colour parsing and encoding.

  Supports the three common forms of ANSI colour used by modern
  terminals:

  * **16-colour palette** — `\\e[30m`..`\\e[37m` (foreground),
    `\\e[40m`..`\\e[47m` (background), plus the bright versions
    `\\e[90m`..`\\e[97m` and `\\e[100m`..`\\e[107m`.

  * **256-colour indexed palette** — `\\e[38;5;Nm` (foreground),
    `\\e[48;5;Nm` (background). Indices 0–15 are the base
    16-colour palette; 16–231 are a 6×6×6 colour cube with levels
    `[0, 95, 135, 175, 215, 255]`; 232–255 are a 24-step grayscale
    ramp starting at 8 with a step of 10.

  * **Truecolor (24-bit)** — `\\e[38;2;R;G;Bm` (foreground),
    `\\e[48;2;R;G;Bm` (background), where `R`, `G` and `B` are
    0..255 bytes.

  The `:mode` option on `to_string/2` selects which form to emit.
  When the target is the 16- or 256-colour palette and the input
  colour isn't an exact palette entry, the encoder picks the
  perceptually nearest palette entry using CIEDE2000 in CIELAB.

  ## Examples

      iex> Color.ANSI.to_string("red") == "\\e[38;2;255;0;0m"
      true

      iex> Color.ANSI.to_string("red", mode: :ansi256) == "\\e[38;5;196m"
      true

      iex> Color.ANSI.to_string("red", mode: :ansi16, layer: :background) == "\\e[101m"
      true

      iex> {:ok, c, :foreground} = Color.ANSI.parse("\\e[38;2;255;0;0m")
      iex> Color.to_hex(c)
      "#ff0000"

      iex> {:ok, c, :background} = Color.ANSI.parse("\\e[41m")
      iex> Color.to_hex(c)
      "#aa0000"

      iex> Color.ANSI.nearest_256("#ff0000")
      196

      iex> Color.ANSI.wrap("hello", "red") == "\\e[38;2;255;0;0mhello\\e[0m"
      true

  """

  # Our `to_string/1,2` has the same arity as `Kernel.to_string/1`.
  # The module-level definition takes precedence inside this file,
  # but the explicit `except:` makes that intent clear and silences
  # any warning on future Elixir versions.
  import Kernel, except: [to_string: 1]

  @typedoc "Which ANSI layer a colour targets."
  @type layer :: :foreground | :background

  @typedoc "How `to_string/2` should encode the colour."
  @type mode :: :truecolor | :ansi256 | :ansi16

  @reset "\e[0m"

  # xterm 16-colour defaults. These are the de-facto VT/xterm
  # values used by most modern terminals. Yellow is `(170, 85, 0)`
  # rather than `(170, 170, 0)` to match xterm's default.
  @palette_16 [
    {0, {0, 0, 0}},
    {1, {170, 0, 0}},
    {2, {0, 170, 0}},
    {3, {170, 85, 0}},
    {4, {0, 0, 170}},
    {5, {170, 0, 170}},
    {6, {0, 170, 170}},
    {7, {170, 170, 170}},
    {8, {85, 85, 85}},
    {9, {255, 85, 85}},
    {10, {85, 255, 85}},
    {11, {255, 255, 85}},
    {12, {85, 85, 255}},
    {13, {255, 85, 255}},
    {14, {85, 255, 255}},
    {15, {255, 255, 255}}
  ]

  # Build the 256-colour palette at compile time.
  #
  #   0-15    — base 16 palette
  #   16-231  — 6×6×6 colour cube with levels [0, 95, 135, 175, 215, 255]
  #   232-255 — 24-step grayscale starting at 8 with a step of 10
  @palette_256 (
    levels = [0, 95, 135, 175, 215, 255]

    cube =
      for i <- 0..215 do
        r = div(i, 36)
        g = div(rem(i, 36), 6)
        b = rem(i, 6)
        {16 + i, {Enum.at(levels, r), Enum.at(levels, g), Enum.at(levels, b)}}
      end

    gray =
      for i <- 0..23 do
        v = 8 + i * 10
        {232 + i, {v, v, v}}
      end

    [
      {0, {0, 0, 0}},
      {1, {170, 0, 0}},
      {2, {0, 170, 0}},
      {3, {170, 85, 0}},
      {4, {0, 0, 170}},
      {5, {170, 0, 170}},
      {6, {0, 170, 170}},
      {7, {170, 170, 170}},
      {8, {85, 85, 85}},
      {9, {255, 85, 85}},
      {10, {85, 255, 85}},
      {11, {255, 255, 85}},
      {12, {85, 85, 255}},
      {13, {255, 85, 255}},
      {14, {85, 255, 255}},
      {15, {255, 255, 255}}
    ] ++ cube ++ gray
  )

  @palette_16_map Map.new(@palette_16)
  @palette_256_map Map.new(@palette_256)

  # ---- public API -------------------------------------------------------

  @doc """
  Parses an ANSI SGR escape sequence and returns the encoded colour.

  The function accepts any of the three canonical ANSI colour forms.
  Style parameters (bold, italic, reverse, …) that precede or
  follow the colour are ignored; only the colour is extracted.
  Sequences that contain no colour descriptor (for example `\\e[0m`
  reset, `\\e[39m` default-foreground, or `\\e[1m` bold-only)
  return an error.

  ### Arguments

  * `sequence` is a binary string starting with `ESC [` and ending
    with `m`. The leading ESC character may be written using the
    Elixir `"\\e"` escape or the raw byte `0x1b`.

  ### Returns

  * `{:ok, %Color.SRGB{}, :foreground | :background}` on success.

  * `{:error, %Color.ANSI.ParseError{}}` if the sequence cannot be
    interpreted.

  """
  @spec parse(binary()) ::
          {:ok, Color.SRGB.t(), layer()} | {:error, Exception.t()}
  def parse(sequence) when is_binary(sequence) do
    case sequence do
      <<"\e[", rest::binary>> ->
        parse_csi(rest, sequence)

      _ ->
        {:error, %Color.ANSI.ParseError{sequence: sequence, reason: :no_csi}}
    end
  end

  @doc """
  Serialises a colour to an ANSI SGR escape sequence.

  ### Arguments

  * `color` is any input accepted by `Color.new/1` — a colour
    struct, a bare list, a hex string, a CSS named colour, or an
    atom.

  * `options` is a keyword list.

  ### Options

  * `:mode` — one of:

    * `:truecolor` (default) — emits `\\e[38;2;R;G;Bm`
      (24-bit, modern terminals only).

    * `:ansi256` — emits `\\e[38;5;Nm` using the perceptually
      nearest 256-colour palette index.

    * `:ansi16` — emits `\\e[30m`..`\\e[37m` or `\\e[90m`..`\\e[97m`
      using the perceptually nearest 16-colour palette index.

  * `:layer` — `:foreground` (default) or `:background`.

  ### Returns

  * A binary string containing the escape sequence.

  ### Examples

      iex> Color.ANSI.to_string("red") == "\\e[38;2;255;0;0m"
      true

      iex> Color.ANSI.to_string(%Color.SRGB{r: 0.0, g: 1.0, b: 0.0}) == "\\e[38;2;0;255;0m"
      true

      iex> Color.ANSI.to_string("red", layer: :background) == "\\e[48;2;255;0;0m"
      true

  """
  @spec to_string(Color.input(), keyword()) :: String.t()
  def to_string(color, options \\ []) do
    mode = Keyword.get(options, :mode, :truecolor)
    layer = Keyword.get(options, :layer, :foreground)

    srgb = to_srgb!(color)
    rgb = to_bytes(srgb)
    encode(mode, layer, rgb, srgb)
  end

  @doc """
  Wraps `string` in the ANSI escape that sets the given colour,
  followed by a reset.

  ### Arguments

  * `string` is any `String.t()`.

  * `color` is any input accepted by `Color.new/1`.

  * `options` is the same as `to_string/2`.

  ### Returns

  * A binary string with the wrapped text.

  ### Examples

      iex> Color.ANSI.wrap("hi", "red") == "\\e[38;2;255;0;0mhi\\e[0m"
      true

      iex> Color.ANSI.wrap("hi", "red", mode: :ansi256) == "\\e[38;5;196mhi\\e[0m"
      true

  """
  @spec wrap(String.t(), Color.input(), keyword()) :: String.t()
  def wrap(string, color, options \\ []) when is_binary(string) do
    __MODULE__.to_string(color, options) <> string <> @reset
  end

  @doc """
  Returns the ANSI reset escape sequence (`ESC[0m`).

  ### Examples

      iex> Color.ANSI.reset() == "\\e[0m"
      true

  """
  @spec reset() :: String.t()
  def reset, do: @reset

  @doc """
  Returns the 256-colour palette index of the entry perceptually
  nearest to `color`, using CIEDE2000 in CIELAB.

  ### Arguments

  * `color` is any input accepted by `Color.new/1`.

  ### Returns

  * An integer in `0..255`.

  ### Examples

      iex> Color.ANSI.nearest_256("#ff0000")
      196

      iex> Color.ANSI.nearest_256("#000000")
      0

  """
  @spec nearest_256(Color.input()) :: 0..255
  def nearest_256(color) do
    srgb = to_srgb!(color)
    nearest_palette_index(@palette_256, srgb)
  end

  @doc """
  Returns the 16-colour palette index of the entry perceptually
  nearest to `color`, using CIEDE2000 in CIELAB.

  ### Arguments

  * `color` is any input accepted by `Color.new/1`.

  ### Returns

  * An integer in `0..15`.

  ### Examples

      iex> Color.ANSI.nearest_16("#ff0000")
      9

      iex> Color.ANSI.nearest_16("#000000")
      0

  """
  @spec nearest_16(Color.input()) :: 0..15
  def nearest_16(color) do
    srgb = to_srgb!(color)
    nearest_palette_index(@palette_16, srgb)
  end

  @doc """
  Returns the full 256-colour palette as a list of
  `{index, {r, g, b}}` tuples, with each channel in `0..255`.

  ### Examples

      iex> length(Color.ANSI.palette_256())
      256

      iex> Enum.find(Color.ANSI.palette_256(), &match?({196, _}, &1))
      {196, {255, 0, 0}}

  """
  @spec palette_256() :: [{0..255, {0..255, 0..255, 0..255}}]
  def palette_256, do: @palette_256

  @doc """
  Returns the 16-colour palette as a list of `{index, {r, g, b}}`
  tuples.

  ### Examples

      iex> length(Color.ANSI.palette_16())
      16

  """
  @spec palette_16() :: [{0..15, {0..255, 0..255, 0..255}}]
  def palette_16, do: @palette_16

  # ---- parsing helpers --------------------------------------------------

  defp parse_csi(rest, full) do
    case String.split(rest, "m", parts: 2) do
      [params, _after] ->
        tokens = String.split(params, ";")
        process_params(tokens, full)

      _ ->
        {:error, %Color.ANSI.ParseError{sequence: full, reason: :no_terminator}}
    end
  end

  defp process_params(tokens, full) do
    case find_colour(tokens) do
      {:ok, layer, r, g, b} ->
        {:ok, Color.SRGB.unscale255({r, g, b}), layer}

      :not_found ->
        {:error, %Color.ANSI.ParseError{sequence: full, reason: :no_colour_param}}

      {:error, reason} ->
        {:error, %Color.ANSI.ParseError{sequence: full, reason: reason}}
    end
  end

  # Walks the parameter list looking for the first colour descriptor.
  # Unknown or style-only params (like `1` for bold) are skipped.
  defp find_colour([]), do: :not_found

  defp find_colour([p | rest]) do
    case Integer.parse(p) do
      {n, ""} -> dispatch(n, rest)
      _ -> find_colour(rest)
    end
  end

  defp dispatch(n, _rest) when n in 30..37 do
    {r, g, b} = Map.fetch!(@palette_16_map, n - 30)
    {:ok, :foreground, r, g, b}
  end

  defp dispatch(n, _rest) when n in 40..47 do
    {r, g, b} = Map.fetch!(@palette_16_map, n - 40)
    {:ok, :background, r, g, b}
  end

  defp dispatch(n, _rest) when n in 90..97 do
    {r, g, b} = Map.fetch!(@palette_16_map, n - 90 + 8)
    {:ok, :foreground, r, g, b}
  end

  defp dispatch(n, _rest) when n in 100..107 do
    {r, g, b} = Map.fetch!(@palette_16_map, n - 100 + 8)
    {:ok, :background, r, g, b}
  end

  defp dispatch(38, ["5", idx | _]), do: parse_indexed(idx, :foreground)
  defp dispatch(48, ["5", idx | _]), do: parse_indexed(idx, :background)

  defp dispatch(38, ["2", r, g, b | _]), do: parse_rgb(r, g, b, :foreground)
  defp dispatch(48, ["2", r, g, b | _]), do: parse_rgb(r, g, b, :background)

  # Unknown numeric param (style code, reset, default fg/bg, etc.)
  # — keep scanning.
  defp dispatch(_, rest), do: find_colour(rest)

  defp parse_indexed(idx_str, layer) do
    case Integer.parse(idx_str) do
      {idx, ""} when idx in 0..255 ->
        {r, g, b} = Map.fetch!(@palette_256_map, idx)
        {:ok, layer, r, g, b}

      _ ->
        {:error, :bad_index}
    end
  end

  defp parse_rgb(r_str, g_str, b_str, layer) do
    with {r, ""} <- Integer.parse(r_str),
         true <- r in 0..255,
         {g, ""} <- Integer.parse(g_str),
         true <- g in 0..255,
         {b, ""} <- Integer.parse(b_str),
         true <- b in 0..255 do
      {:ok, layer, r, g, b}
    else
      _ -> {:error, :bad_rgb}
    end
  end

  # ---- encoding helpers -------------------------------------------------

  defp encode(:truecolor, :foreground, {r, g, b}, _srgb) do
    "\e[38;2;#{r};#{g};#{b}m"
  end

  defp encode(:truecolor, :background, {r, g, b}, _srgb) do
    "\e[48;2;#{r};#{g};#{b}m"
  end

  defp encode(:ansi256, layer, _rgb, srgb) do
    idx = nearest_palette_index(@palette_256, srgb)
    prefix = layer_prefix(layer)
    "\e[#{prefix};5;#{idx}m"
  end

  defp encode(:ansi16, layer, _rgb, srgb) do
    idx = nearest_palette_index(@palette_16, srgb)
    "\e[#{sgr_code_16(idx, layer)}m"
  end

  defp encode(mode, _, _, _) do
    raise ArgumentError,
          "Unknown Color.ANSI mode #{inspect(mode)}. Valid modes: " <>
            ":truecolor, :ansi256, :ansi16."
  end

  defp layer_prefix(:foreground), do: "38"
  defp layer_prefix(:background), do: "48"

  defp sgr_code_16(idx, :foreground) when idx < 8, do: 30 + idx
  defp sgr_code_16(idx, :foreground), do: 90 + idx - 8
  defp sgr_code_16(idx, :background) when idx < 8, do: 40 + idx
  defp sgr_code_16(idx, :background), do: 100 + idx - 8

  # Perceptual nearest-palette match using CIEDE2000.
  # The palette is small (16 or 256), so this is fast enough for
  # ANSI output paths without precomputation.
  defp nearest_palette_index(palette, %Color.SRGB{} = source) do
    {idx, _rgb} =
      Enum.min_by(palette, fn {_idx, {r, g, b}} ->
        candidate = %Color.SRGB{r: r / 255, g: g / 255, b: b / 255}
        Color.Distance.delta_e_2000(source, candidate)
      end)

    idx
  end

  defp to_srgb!(color) do
    case Color.new(color) do
      {:ok, %Color.SRGB{} = srgb} ->
        srgb

      {:ok, other} ->
        case Color.convert(other, Color.SRGB) do
          {:ok, srgb} -> srgb
          {:error, exception} -> raise exception
        end

      {:error, exception} ->
        raise exception
    end
  end

  defp to_bytes(%Color.SRGB{r: r, g: g, b: b}) do
    {clamp_byte(r), clamp_byte(g), clamp_byte(b)}
  end

  defp clamp_byte(v) do
    v
    |> max(0.0)
    |> min(1.0)
    |> Kernel.*(255)
    |> round()
  end
end
