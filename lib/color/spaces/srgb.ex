defmodule Color.SRGB do
  @moduledoc """
  sRGB color space, using the Lindbloom sRGB working space
  (primaries from IEC 61966-2-1, D65 reference white) and the sRGB
  companding function.

  Channels `r`, `g` and `b` are unit floats in the nominal range `[0, 1]`.
  The legacy 0..255 convention is not used — convert with
  `scale255/1` / `unscale255/1` if you need 8-bit values.

  """

  @behaviour Color.Behaviour

  alias Color.Conversion.Lindbloom

  defstruct [:r, :g, :b, :alpha]

  @type t :: %__MODULE__{
          r: number() | nil,
          g: number() | nil,
          b: number() | nil,
          alpha: number() | nil
        }

  {:ok, info} = Color.RGB.WorkingSpace.rgb_conversion_matrix(:SRGB)
  @to_xyz_matrix info.to_xyz
  @from_xyz_matrix info.from_xyz
  @illuminant info.illuminant
  @observer_angle info.observer_angle

  @doc """
  Converts an sRGB color to a CIE `XYZ` color.

  ### Arguments

  * `srgb` is a `Color.SRGB` struct with unit-range channels.

  ### Returns

  * A `Color.XYZ` struct tagged with the sRGB working space illuminant
    (`:D65`, 2° observer). `Y ∈ [0, 1]`.

  ### Examples

      iex> {:ok, xyz} = Color.SRGB.to_xyz(%Color.SRGB{r: 1.0, g: 1.0, b: 1.0})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0888}

  """
  @spec to_xyz(t()) :: {:ok, Color.XYZ.t()}
  def to_xyz(%__MODULE__{r: r, g: g, b: b, alpha: alpha}) do
    linear = {
      Lindbloom.srgb_inverse_compand(r),
      Lindbloom.srgb_inverse_compand(g),
      Lindbloom.srgb_inverse_compand(b)
    }

    {x, y, z} = Lindbloom.rgb_to_xyz(linear, @to_xyz_matrix)

    {:ok,
     %Color.XYZ{
       x: x,
       y: y,
       z: z,
       alpha: alpha,
       illuminant: @illuminant,
       observer_angle: @observer_angle
     }}
  end

  @doc """
  Converts a CIE `XYZ` color to sRGB.

  This assumes the `xyz` is already in the sRGB working space's reference
  white (D65/2°). If your `XYZ` is under a different illuminant, adapt it
  with `Color.ChromaticAdaptation` first.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct on the `Y ∈ [0, 1]` scale.

  ### Returns

  * A `Color.SRGB` struct.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, srgb} = Color.SRGB.from_xyz(xyz)
      iex> {Float.round(srgb.r, 4), Float.round(srgb.g, 4), Float.round(srgb.b, 4)}
      {1.0, 1.0, 1.0}

  """
  @spec from_xyz(Color.XYZ.t()) :: {:ok, t()}
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}) do
    {lr, lg, lb} = Lindbloom.xyz_to_rgb({x, y, z}, @from_xyz_matrix)

    {:ok,
     %__MODULE__{
       r: Lindbloom.srgb_compand(lr),
       g: Lindbloom.srgb_compand(lg),
       b: Lindbloom.srgb_compand(lb),
       alpha: alpha
     }}
  end

  @doc """
  Scales unit-range sRGB channels to the conventional 0..255 byte range.

  ### Arguments

  * `srgb` is a `Color.SRGB` struct with unit-range channels.

  ### Returns

  * A `{r, g, b}` tuple of floats in `[0, 255]`.

  ### Examples

      iex> Color.SRGB.scale255(%Color.SRGB{r: 1.0, g: 0.5, b: 0.0})
      {255.0, 127.5, 0.0}

  """
  def scale255(%__MODULE__{r: r, g: g, b: b}), do: {r * 255, g * 255, b * 255}

  @doc """
  Builds an sRGB struct from 0..255 byte channels.

  ### Arguments

  * `rgb` is an `{r, g, b}` tuple of numbers in `[0, 255]`.

  * `alpha` is an optional alpha value, defaults to `nil`.

  ### Returns

  * A `Color.SRGB` struct with unit-range channels.

  ### Examples

      iex> Color.SRGB.unscale255({255, 0, 0})
      %Color.SRGB{r: 1.0, g: 0.0, b: 0.0, alpha: nil}

  """
  def unscale255({r, g, b}, alpha \\ nil) do
    %__MODULE__{r: r / 255, g: g / 255, b: b / 255, alpha: alpha}
  end

  @doc """
  Parses a CSS hex color or CSS named color into an sRGB struct.

  Accepts any of the CSS Color Module Level 4 hex forms:

  * `#RGB` — 4-bit-per-channel shorthand (e.g. `#f80`).

  * `#RGBA` — shorthand with alpha.

  * `#RRGGBB` — 8-bit per channel.

  * `#RRGGBBAA` — 8-bit per channel with alpha.

  The leading `#` is optional. Parsing is case-insensitive. Any other
  string is looked up in `Color.CSS.Names`, so named colors like
  `"rebeccapurple"` also work.

  ### Arguments

  * `input` is a string.

  ### Returns

  * `{:ok, %Color.SRGB{}}` with unit-range channels.

  * `{:error, reason}` if the input can't be parsed.

  ### Examples

      iex> {:ok, red} = Color.SRGB.parse("#ff0000")
      iex> {red.r, red.g, red.b}
      {1.0, 0.0, 0.0}

      iex> {:ok, c} = Color.SRGB.parse("#f80")
      iex> {c.r, c.g, c.b}
      {1.0, 0.5333333333333333, 0.0}

      iex> {:ok, c} = Color.SRGB.parse("rebeccapurple")
      iex> {c.r, c.g, c.b}
      {0.4, 0.2, 0.6}

      iex> {:ok, c} = Color.SRGB.parse("#ff000080")
      iex> {c.r, c.g, c.b, Float.round(c.alpha, 4)}
      {1.0, 0.0, 0.0, 0.502}

  """
  def parse("#" <> rest), do: parse_hex(rest)

  def parse(string) when is_binary(string) do
    cond do
      hex_like?(string) ->
        parse_hex(string)

      true ->
        with {:ok, rgb} <- Color.CSS.Names.lookup(string) do
          {:ok, unscale255(rgb)}
        end
    end
  end

  defp hex_like?(string) do
    byte_size(string) in [3, 4, 6, 8] and
      String.match?(string, ~r/^[0-9a-fA-F]+$/)
  end

  defp parse_hex(hex) do
    original = hex
    hex = String.downcase(hex)

    case String.length(hex) do
      3 ->
        [r, g, b] = String.graphemes(hex)

        with {:ok, {r, g, b}} <- parse_bytes([r <> r, g <> g, b <> b], original) do
          {:ok, unscale255({r, g, b})}
        end

      4 ->
        [r, g, b, a] = String.graphemes(hex)

        with {:ok, {r, g, b, a}} <-
               parse_bytes_alpha([r <> r, g <> g, b <> b, a <> a], original) do
          {:ok, %__MODULE__{r: r / 255, g: g / 255, b: b / 255, alpha: a / 255}}
        end

      6 ->
        <<r::binary-2, g::binary-2, b::binary-2>> = hex

        with {:ok, {r, g, b}} <- parse_bytes([r, g, b], original) do
          {:ok, unscale255({r, g, b})}
        end

      8 ->
        <<r::binary-2, g::binary-2, b::binary-2, a::binary-2>> = hex

        with {:ok, {r, g, b, a}} <- parse_bytes_alpha([r, g, b, a], original) do
          {:ok, %__MODULE__{r: r / 255, g: g / 255, b: b / 255, alpha: a / 255}}
        end

      _ ->
        {:error, %Color.InvalidHexError{hex: original, reason: :bad_length}}
    end
  end

  defp parse_bytes(list, original) do
    list
    |> Enum.reduce_while({:ok, []}, fn s, {:ok, acc} ->
      case Integer.parse(s, 16) do
        {n, ""} when n in 0..255 ->
          {:cont, {:ok, [n | acc]}}

        _ ->
          {:halt, {:error, %Color.InvalidHexError{hex: original, reason: :bad_byte}}}
      end
    end)
    |> case do
      {:ok, [b, g, r]} -> {:ok, {r, g, b}}
      other -> other
    end
  end

  defp parse_bytes_alpha(list, original) do
    list
    |> Enum.reduce_while({:ok, []}, fn s, {:ok, acc} ->
      case Integer.parse(s, 16) do
        {n, ""} when n in 0..255 ->
          {:cont, {:ok, [n | acc]}}

        _ ->
          {:halt, {:error, %Color.InvalidHexError{hex: original, reason: :bad_byte}}}
      end
    end)
    |> case do
      {:ok, [a, b, g, r]} -> {:ok, {r, g, b, a}}
      other -> other
    end
  end

  @doc """
  Formats an sRGB color as a CSS hex string.

  Channels are clamped to `[0, 1]` and rounded to 8 bits. If the alpha
  channel is `nil` or `1.0`, a six-digit `#RRGGBB` is produced.
  Otherwise an eight-digit `#RRGGBBAA` is produced.

  ### Arguments

  * `srgb` is a `Color.SRGB` struct.

  ### Returns

  * A lowercase hex string starting with `#`.

  ### Examples

      iex> Color.SRGB.to_hex(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0})
      "#ff0000"

      iex> Color.SRGB.to_hex(%Color.SRGB{r: 1.0, g: 0.5333333, b: 0.0})
      "#ff8800"

      iex> Color.SRGB.to_hex(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0, alpha: 0.5})
      "#ff000080"

  """
  def to_hex(%__MODULE__{r: r, g: g, b: b, alpha: alpha}) do
    {r8, g8, b8} = {clamp_byte(r), clamp_byte(g), clamp_byte(b)}

    case alpha do
      nil -> "#" <> hex2(r8) <> hex2(g8) <> hex2(b8)
      1.0 -> "#" <> hex2(r8) <> hex2(g8) <> hex2(b8)
      a -> "#" <> hex2(r8) <> hex2(g8) <> hex2(b8) <> hex2(clamp_byte(a))
    end
  end

  defp clamp_byte(v) do
    v
    |> max(0.0)
    |> min(1.0)
    |> Kernel.*(255)
    |> round()
  end

  defp hex2(n) do
    n
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(2, "0")
  end
end
