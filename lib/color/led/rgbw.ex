defmodule Color.LED.RGBW do
  @moduledoc """
  A four-channel **RGBW** LED pixel — red, green, blue plus one
  fixed-temperature white channel.

  This is the pixel format used by the **WS2814** family (warm,
  neutral, cool variants) and the **SK6812-RGBW** family, among
  others. Each addressable pixel has three coloured LEDs plus a
  single white LED whose colour temperature is fixed by the chip
  variant.

  All four channels — `:r`, `:g`, `:b`, `:w` — are **linear drive
  values in `[0.0, 1.0]`**. `0.0` means the LED is off, `1.0` means
  at full drive. They are *not* sRGB-companded values; companding
  is applied when converting from / to `Color.SRGB`.

  ## Fields

  * `:r`, `:g`, `:b` — linear drive for the red, green, blue LEDs.

  * `:w` — linear drive for the white LED.

  * `:white_temperature` — the correlated colour temperature (in
    Kelvin) of the white LED. Stored on the struct so the pixel is
    self-describing and round-trippable.

  * `:alpha` — optional alpha in `[0.0, 1.0]`, or `nil`.

  ## Converting sRGB → RGBW

      iex> {:ok, target} = Color.new("#ffa500")
      iex> pixel = Color.LED.RGBW.from_srgb(target, white_temperature: 4500)
      iex> match?(%Color.LED.RGBW{white_temperature: 4500}, pixel)
      true

  The extraction picks the largest white drive that keeps every
  R/G/B channel non-negative. See `Color.LED` for the algorithm.

  ## Converting RGBW → sRGB

  Use `to_srgb/1` to simulate what the pixel actually emits, for
  preview or gamut-checking. This applies the white LED's spectral
  output on top of the coloured LEDs and companded-clamps the
  result to the sRGB display space.

  """

  alias Color.LED

  @enforce_keys [:r, :g, :b, :w, :white_temperature]
  defstruct [:r, :g, :b, :w, :white_temperature, alpha: nil]

  @type t :: %__MODULE__{
          r: float(),
          g: float(),
          b: float(),
          w: float(),
          white_temperature: number(),
          alpha: Color.Types.alpha() | nil
        }

  @doc """
  Builds an RGBW pixel from an sRGB colour for a fixture whose
  white LED has the given colour temperature.

  The algorithm picks the largest `w` that keeps `r`, `g`, `b`
  non-negative and `w ≤ 1`, maximising how much light comes from
  the (usually more efficient) white LED.

  ### Arguments

  * `srgb` is any value accepted by `Color.new/1` — a
    `Color.SRGB` struct, a hex string, a CSS named colour, etc.

  ### Options

  * `:white_temperature` is the correlated colour temperature of
    the white LED, in Kelvin. Required.

  * `:chip` is an alternative to `:white_temperature`: pass a chip
    atom from `Color.LED.chips/0` and the temperature is looked up
    from `Color.LED.chip_options/1`. Only RGBW chips are accepted.

  ### Returns

  * A `Color.LED.RGBW` struct.

  ### Examples

      iex> {:ok, white} = Color.new("#ffffff")
      iex> pixel = Color.LED.RGBW.from_srgb(white, white_temperature: 6500)
      iex> Float.round(pixel.w, 3)
      1.0

      iex> {:ok, red} = Color.new("#ff0000")
      iex> pixel = Color.LED.RGBW.from_srgb(red, chip: :ws2814_nw)
      iex> Float.round(pixel.r, 3) > 0.9
      true

  """
  @spec from_srgb(Color.input(), keyword()) :: t()
  def from_srgb(srgb, options \\ []) do
    cct = resolve_cct!(options)
    {:ok, srgb} = Color.new(srgb)

    {lr, lg, lb} = LED.linearise(srgb)
    white_rgb = LED.white_linear_rgb(cct)

    {w, {r2, g2, b2}} = LED.extract_white({lr, lg, lb}, white_rgb)

    %__MODULE__{
      r: r2,
      g: g2,
      b: b2,
      w: w,
      white_temperature: cct,
      alpha: srgb.alpha
    }
  end

  @doc """
  Simulates what an RGBW pixel actually emits, as a companded
  `Color.SRGB` struct.

  The result is clamped to the sRGB cube — pixels that over-drive
  any display channel will saturate. Use this for preview, gamut
  checking, or to round-trip back to any other colour space.

  ### Arguments

  * `pixel` is a `Color.LED.RGBW` struct.

  ### Returns

  * `{:ok, %Color.SRGB{}}`.

  ### Examples

      iex> {:ok, target} = Color.new("#ffa500")
      iex> pixel = Color.LED.RGBW.from_srgb(target, white_temperature: 4500)
      iex> {:ok, srgb} = Color.LED.RGBW.to_srgb(pixel)
      iex> match?(%Color.SRGB{}, srgb)
      true

  """
  @spec to_srgb(t()) :: {:ok, Color.SRGB.t()}
  def to_srgb(%__MODULE__{r: r, g: g, b: b, w: w, white_temperature: cct, alpha: alpha}) do
    {wr, wg, wb} = LED.white_linear_rgb(cct)

    linear = {
      r + w * wr,
      g + w * wg,
      b + w * wb
    }

    {:ok, LED.compand(linear, alpha)}
  end

  @doc """
  Converts an RGBW pixel to `Color.XYZ` by simulating its emitted
  light and running the standard sRGB → XYZ path.

  ### Arguments

  * `pixel` is a `Color.LED.RGBW` struct.

  ### Returns

  * `{:ok, %Color.XYZ{}}` on success, `{:error, exception}` on
    failure.

  ### Examples

      iex> {:ok, target} = Color.new("#336699")
      iex> pixel = Color.LED.RGBW.from_srgb(target, white_temperature: 3000)
      iex> {:ok, xyz} = Color.LED.RGBW.to_xyz(pixel)
      iex> match?(%Color.XYZ{}, xyz)
      true

  """
  @spec to_xyz(t()) :: {:ok, Color.XYZ.t()} | {:error, Exception.t()}
  def to_xyz(%__MODULE__{} = pixel) do
    with {:ok, srgb} <- to_srgb(pixel) do
      Color.convert(srgb, Color.XYZ)
    end
  end

  # ---- helpers ----------------------------------------------------------

  defp resolve_cct!(options) do
    cond do
      cct = Keyword.get(options, :white_temperature) ->
        unless is_number(cct),
          do: raise(ArgumentError, ":white_temperature must be a number in Kelvin")

        cct

      chip = Keyword.get(options, :chip) ->
        chip_opts = Color.LED.chip_options(chip)

        case Keyword.get(chip_opts, :kind) do
          :rgbw ->
            Keyword.fetch!(chip_opts, :white_temperature)

          other ->
            raise ArgumentError,
                  "chip #{inspect(chip)} is not an RGBW chip (kind: #{inspect(other)})"
        end

      true ->
        raise ArgumentError,
              "Color.LED.RGBW.from_srgb/2 requires :white_temperature or :chip"
    end
  end
end
