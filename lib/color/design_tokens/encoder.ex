defmodule Color.DesignTokens.Encoder do
  @moduledoc false

  # Per-space encoders for the W3C DTCG 2025.10 Color spec.
  #
  # Each encode/1 clause pattern-matches a Color.* struct and
  # returns a map shaped as DTCG's `$value`:
  #
  #   %{
  #     "colorSpace" => "oklch",
  #     "components" => [l, c, h],
  #     "alpha" => 1.0,
  #     "hex" => "#rrggbb"
  #   }
  #
  # Hex fallback is always emitted — it's cheap and doubles the
  # compatibility with tools that don't yet grok Oklab / Oklch.

  @doc """
  Encodes a `Color.*` struct into a DTCG `$value` map.

  If the struct is not in the caller's desired target space, the
  caller should convert it first via `Color.convert/2`.
  """
  @spec encode(struct()) :: map()
  def encode(struct)

  def encode(%Color.SRGB{r: r, g: g, b: b, alpha: alpha} = color) do
    value("srgb", [r, g, b], alpha, color)
  end

  def encode(%Color.HSL{h: h, s: s, l: l, alpha: alpha} = color) do
    value("hsl", [h, s, l], alpha, color)
  end

  def encode(%Color.Lab{l: l, a: a, b: b, alpha: alpha} = color) do
    value("lab", [l, a, b], alpha, color)
  end

  def encode(%Color.LCHab{l: l, c: c, h: h, alpha: alpha} = color) do
    value("lch", [l, c, h], alpha, color)
  end

  def encode(%Color.Oklab{l: l, a: a, b: b, alpha: alpha} = color) do
    value("oklab", [l, a, b], alpha, color)
  end

  def encode(%Color.Oklch{l: l, c: c, h: h, alpha: alpha} = color) do
    value("oklch", [l, c, h], alpha, color)
  end

  def encode(%Color.AdobeRGB{r: r, g: g, b: b, alpha: alpha} = color) do
    value("a98-rgb", [r, g, b], alpha, color)
  end

  # XYZ: DTCG splits on illuminant. D50 and D65 are the two
  # spellings accepted by the spec.
  def encode(%Color.XYZ{illuminant: :D50} = xyz) do
    value("xyz-d50", [xyz.x, xyz.y, xyz.z], xyz.alpha, xyz)
  end

  def encode(%Color.XYZ{} = xyz) do
    # Default / D65 / nil all map to the DTCG "xyz-d65" space,
    # consistent with the rest of the library treating unset
    # illuminant as D65.
    value("xyz-d65", [xyz.x, xyz.y, xyz.z], xyz.alpha, xyz)
  end

  # Color.RGB in a named working space. DTCG names vary by space.
  def encode(%Color.RGB{working_space: ws, r: r, g: g, b: b, alpha: alpha} = rgb) do
    space = working_space_to_dtcg(ws)
    value(space, [r, g, b], alpha, rgb)
  end

  # For every other supported struct, the caller is expected to
  # convert first. If they haven't, it's a programmer error — raise.
  def encode(other) do
    raise ArgumentError,
          "Color.DesignTokens does not support encoding #{inspect(other.__struct__)} directly. " <>
            "Convert via Color.convert/2 to one of the DTCG-supported spaces first " <>
            "(SRGB, HSL, Lab, LCHab, Oklab, Oklch, XYZ, AdobeRGB, or RGB in :P3/:Rec2020/:ProPhoto/:SRGB)."
  end

  # ---- helpers ------------------------------------------------------------

  defp value(space, components, alpha, original_struct) do
    base = %{
      "colorSpace" => space,
      "components" => Enum.map(components, &round_component/1),
      "hex" => hex_or_nil(original_struct)
    }

    case alpha do
      nil -> base
      a when is_number(a) -> Map.put(base, "alpha", round_component(a))
    end
  end

  # DTCG components are numbers. We round to 6 decimal places
  # which is lossless enough for any practical re-decode.
  defp round_component(nil), do: 0.0

  defp round_component(n) when is_float(n), do: Float.round(n, 6)

  defp round_component(n) when is_integer(n), do: n * 1.0

  defp round_component(n), do: n

  defp hex_or_nil(struct) do
    Color.to_hex(struct)
  rescue
    _ -> nil
  end

  defp working_space_to_dtcg(:SRGB), do: "srgb-linear"
  defp working_space_to_dtcg(:P3), do: "display-p3"
  defp working_space_to_dtcg(:DisplayP3), do: "display-p3"
  defp working_space_to_dtcg(:Rec2020), do: "rec2020"
  defp working_space_to_dtcg(:ProPhoto), do: "prophoto-rgb"

  defp working_space_to_dtcg(other) do
    raise ArgumentError,
          "Color.DesignTokens cannot encode a %Color.RGB{} in working space #{inspect(other)}. " <>
            "DTCG supports :SRGB (→ srgb-linear), :P3, :Rec2020, :ProPhoto. " <>
            "Convert to one of those via Color.convert/3, or go via a companded space like SRGB/AdobeRGB."
  end
end
