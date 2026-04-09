defmodule Color.LED.RGBWW do
  @moduledoc """
  A five-channel **RGBWW** / **RGB+CCT** LED pixel — red, green,
  blue plus a **warm white** and a **cool white** channel.

  This is the pixel format used by the **WS2805** family and
  several SK6812 variants. The warm and cool white LEDs can be
  blended to reach any correlated colour temperature along the
  line between them, giving much better white rendering than a
  plain RGB pixel and more flexibility than single-temperature
  RGBW.

  All five channels — `:r`, `:g`, `:b`, `:ww`, `:cw` — are
  **linear drive values in `[0.0, 1.0]`**, not sRGB-companded.

  ## Fields

  * `:r`, `:g`, `:b` — linear drive for the red, green, blue LEDs.

  * `:ww` — linear drive for the warm white LED.

  * `:cw` — linear drive for the cool white LED.

  * `:warm_temperature` — CCT (Kelvin) of the warm white LED.

  * `:cool_temperature` — CCT (Kelvin) of the cool white LED.

  * `:alpha` — optional alpha in `[0.0, 1.0]`, or `nil`.

  ## Extraction

  `from_srgb/2` finds the target's CCT, clamps it to
  `[warm_temperature, cool_temperature]`, picks a blend ratio
  between the two whites that matches that CCT, synthesises a
  single "mixed white" at that blend, runs the RGBW extraction
  against it, and splits the resulting total white drive back
  into `:ww` and `:cw` by the same ratio.

  ## Example

      iex> options = Color.LED.chip_options(:ws2805)
      iex> {:ok, target} = Color.new("#ffa500")
      iex> pixel = Color.LED.RGBWW.from_srgb(target, options)
      iex> match?(%Color.LED.RGBWW{warm_temperature: 3000, cool_temperature: 6500}, pixel)
      true

  """

  alias Color.LED

  @enforce_keys [:r, :g, :b, :ww, :cw, :warm_temperature, :cool_temperature]
  defstruct [:r, :g, :b, :ww, :cw, :warm_temperature, :cool_temperature, alpha: nil]

  @type t :: %__MODULE__{
          r: float(),
          g: float(),
          b: float(),
          ww: float(),
          cw: float(),
          warm_temperature: number(),
          cool_temperature: number(),
          alpha: Color.Types.alpha() | nil
        }

  @doc """
  Builds an RGBWW pixel from an sRGB colour for a fixture whose
  warm and cool white LEDs have the given colour temperatures.

  ### Arguments

  * `srgb` is any value accepted by `Color.new/1`.

  ### Options

  * `:warm_temperature` is the warm white LED's CCT in Kelvin.

  * `:cool_temperature` is the cool white LED's CCT in Kelvin.

  * `:chip` is an alternative to supplying the two temperatures
    explicitly: pass a chip atom from `Color.LED.chips/0` and the
    temperatures are looked up from `Color.LED.chip_options/1`.
    Only RGBWW chips are accepted.

  ### Returns

  * A `Color.LED.RGBWW` struct.

  ### Examples

      iex> {:ok, white} = Color.new("#ffffff")
      iex> pixel = Color.LED.RGBWW.from_srgb(white, chip: :ws2805)
      iex> Float.round(pixel.ww + pixel.cw, 3) > 0.9
      true

  """
  @spec from_srgb(Color.input(), keyword()) :: t()
  def from_srgb(srgb, options \\ []) do
    {warm, cool} = resolve_temperatures!(options)
    {:ok, srgb} = Color.new(srgb)

    {lr, lg, lb} = LED.linearise(srgb)

    # Find the target's CCT. Fall back to the mid-point if the
    # target is achromatic (cct/1 can return nonsense for pure
    # black / saturated primaries outside the locus).
    target_cct = safe_cct(srgb, (warm + cool) / 2)

    # Clamp into the [warm, cool] range the fixture can actually
    # reach with its two white LEDs.
    clamped_cct = clamp_number(target_cct, min(warm, cool), max(warm, cool))

    # Blend ratio: 0.0 = all warm, 1.0 = all cool. Linear in CCT.
    # This is a pragmatic approximation — linear blending in CCT
    # is not strictly linear in chromaticity, but it's close
    # enough over a narrow warm-cool range and fixtures are
    # usually calibrated by eye anyway.
    ratio =
      if cool == warm do
        0.0
      else
        (clamped_cct - warm) / (cool - warm)
      end

    {wwr, wwg, wwb} = LED.white_linear_rgb(warm)
    {cwr, cwg, cwb} = LED.white_linear_rgb(cool)

    # Effective "mixed white" in linear sRGB at that blend.
    mixed = {
      (1 - ratio) * wwr + ratio * cwr,
      (1 - ratio) * wwg + ratio * cwg,
      (1 - ratio) * wwb + ratio * cwb
    }

    {w_total, {r2, g2, b2}} = LED.extract_white({lr, lg, lb}, mixed)

    # Split the total white drive back into warm and cool.
    ww = w_total * (1 - ratio)
    cw = w_total * ratio

    %__MODULE__{
      r: r2,
      g: g2,
      b: b2,
      ww: ww,
      cw: cw,
      warm_temperature: warm,
      cool_temperature: cool,
      alpha: srgb.alpha
    }
  end

  @doc """
  Simulates what an RGBWW pixel actually emits, as a companded
  `Color.SRGB` struct.

  ### Arguments

  * `pixel` is a `Color.LED.RGBWW` struct.

  ### Returns

  * `{:ok, %Color.SRGB{}}`.

  ### Examples

      iex> {:ok, target} = Color.new("#ffa500")
      iex> pixel = Color.LED.RGBWW.from_srgb(target, chip: :ws2805)
      iex> {:ok, srgb} = Color.LED.RGBWW.to_srgb(pixel)
      iex> match?(%Color.SRGB{}, srgb)
      true

  """
  @spec to_srgb(t()) :: {:ok, Color.SRGB.t()}
  def to_srgb(%__MODULE__{
        r: r,
        g: g,
        b: b,
        ww: ww,
        cw: cw,
        warm_temperature: warm,
        cool_temperature: cool,
        alpha: alpha
      }) do
    {wwr, wwg, wwb} = LED.white_linear_rgb(warm)
    {cwr, cwg, cwb} = LED.white_linear_rgb(cool)

    linear = {
      r + ww * wwr + cw * cwr,
      g + ww * wwg + cw * cwg,
      b + ww * wwb + cw * cwb
    }

    {:ok, LED.compand(linear, alpha)}
  end

  @doc """
  Converts an RGBWW pixel to `Color.XYZ` by simulating its
  emitted light.

  ### Arguments

  * `pixel` is a `Color.LED.RGBWW` struct.

  ### Returns

  * `{:ok, %Color.XYZ{}}` on success, `{:error, exception}` on
    failure.

  ### Examples

      iex> {:ok, target} = Color.new("#336699")
      iex> pixel = Color.LED.RGBWW.from_srgb(target, chip: :ws2805)
      iex> {:ok, xyz} = Color.LED.RGBWW.to_xyz(pixel)
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

  defp resolve_temperatures!(options) do
    cond do
      chip = Keyword.get(options, :chip) ->
        chip_opts = Color.LED.chip_options(chip)

        case Keyword.get(chip_opts, :kind) do
          :rgbww ->
            {
              Keyword.fetch!(chip_opts, :warm_temperature),
              Keyword.fetch!(chip_opts, :cool_temperature)
            }

          other ->
            raise ArgumentError,
                  "chip #{inspect(chip)} is not an RGBWW chip (kind: #{inspect(other)})"
        end

      Keyword.has_key?(options, :warm_temperature) or
          Keyword.has_key?(options, :cool_temperature) ->
        warm = Keyword.fetch!(options, :warm_temperature)
        cool = Keyword.fetch!(options, :cool_temperature)

        unless is_number(warm) and is_number(cool) do
          raise ArgumentError,
                ":warm_temperature and :cool_temperature must be numbers in Kelvin"
        end

        {warm, cool}

      # Allow passing a chip_options/1 keyword list directly.
      Keyword.get(options, :kind) == :rgbww ->
        {
          Keyword.fetch!(options, :warm_temperature),
          Keyword.fetch!(options, :cool_temperature)
        }

      true ->
        raise ArgumentError,
              "Color.LED.RGBWW.from_srgb/2 requires :warm_temperature + :cool_temperature or :chip"
    end
  end

  defp safe_cct(%Color.SRGB{} = srgb, fallback) do
    case Color.Temperature.cct(srgb) do
      n when is_number(n) and n > 0 -> n
      _ -> fallback
    end
  rescue
    _ -> fallback
  end

  defp clamp_number(v, lo, _hi) when v < lo, do: lo
  defp clamp_number(v, _lo, hi) when v > hi, do: hi
  defp clamp_number(v, _lo, _hi), do: v
end
