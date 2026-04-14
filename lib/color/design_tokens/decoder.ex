defmodule Color.DesignTokens.Decoder do
  @moduledoc false

  # Decoder for DTCG 2025.10 color tokens. Accepts either a full
  # token (with "$type" / "$value") or a bare "$value" map, and
  # returns {:ok, struct} or {:error, exception}.

  alias Color.DesignTokensDecodeError

  @doc """
  Decodes a DTCG color token (or bare `$value` map) into a
  `Color.*` struct.
  """
  @spec decode(map() | binary()) :: {:ok, struct()} | {:error, Exception.t()}
  def decode(input)

  # Alias token — we don't resolve aliases in v1.
  def decode(<<"{", _::binary>> = alias_string) do
    {:error,
     %DesignTokensDecodeError{
       reason: :alias_not_resolved,
       detail:
         "Design token alias #{inspect(alias_string)} cannot be decoded in isolation. " <>
           "Resolve aliases in the caller before handing values to this module."
     }}
  end

  def decode(%{"$type" => "color", "$value" => value}), do: decode(value)

  def decode(%{"$type" => type}) when is_binary(type) and type != "color" do
    {:error,
     %DesignTokensDecodeError{
       reason: :not_a_color_token,
       detail: "$type was #{inspect(type)}, expected \"color\""
     }}
  end

  # Bare $value map — the normal path.
  def decode(%{"colorSpace" => space, "components" => components} = value)
      when is_binary(space) and is_list(components) do
    alpha = Map.get(value, "alpha")

    with :ok <- validate_alpha(alpha),
         {:ok, struct} <- from_components(space, components, alpha) do
      {:ok, struct}
    end
  end

  # Only a hex fallback given. The spec says hex is optional but
  # when it's the only usable payload we should accept it.
  def decode(%{"hex" => hex}) when is_binary(hex) do
    case Color.new(hex) do
      {:ok, srgb} ->
        {:ok, srgb}

      {:error, _} ->
        {:error, %DesignTokensDecodeError{reason: :bad_hex, detail: inspect(hex)}}
    end
  end

  def decode(%{}) do
    {:error,
     %DesignTokensDecodeError{
       reason: :missing_field,
       detail: "token $value must contain \"colorSpace\" + \"components\" or at least \"hex\""
     }}
  end

  def decode(other) do
    {:error,
     %DesignTokensDecodeError{
       reason: :not_a_color_token,
       detail: "expected a map, got #{inspect(other)}"
     }}
  end

  # ---- per-space construction --------------------------------------------

  defp from_components("srgb", [r, g, b], alpha) do
    ok(%Color.SRGB{r: num(r), g: num(g), b: num(b), alpha: alpha_or_nil(alpha)})
  end

  defp from_components("hsl", [h, s, l], alpha) do
    ok(%Color.HSL{h: num(h), s: num(s), l: num(l), alpha: alpha_or_nil(alpha)})
  end

  defp from_components("lab", [l, a, b], alpha) do
    ok(%Color.Lab{l: num(l), a: num(a), b: num(b), alpha: alpha_or_nil(alpha)})
  end

  defp from_components("lch", [l, c, h], alpha) do
    ok(%Color.LCHab{l: num(l), c: num(c), h: num(h), alpha: alpha_or_nil(alpha)})
  end

  defp from_components("oklab", [l, a, b], alpha) do
    ok(%Color.Oklab{l: num(l), a: num(a), b: num(b), alpha: alpha_or_nil(alpha)})
  end

  defp from_components("oklch", [l, c, h], alpha) do
    ok(%Color.Oklch{l: num(l), c: num(c), h: num(h), alpha: alpha_or_nil(alpha)})
  end

  defp from_components("a98-rgb", [r, g, b], alpha) do
    ok(%Color.AdobeRGB{r: num(r), g: num(g), b: num(b), alpha: alpha_or_nil(alpha)})
  end

  defp from_components("xyz-d50", [x, y, z], alpha) do
    ok(%Color.XYZ{
      x: num(x),
      y: num(y),
      z: num(z),
      alpha: alpha_or_nil(alpha),
      illuminant: :D50,
      observer_angle: 2
    })
  end

  defp from_components("xyz-d65", [x, y, z], alpha) do
    ok(%Color.XYZ{
      x: num(x),
      y: num(y),
      z: num(z),
      alpha: alpha_or_nil(alpha),
      illuminant: :D65,
      observer_angle: 2
    })
  end

  # DTCG "xyz" (no illuminant suffix) defaults to D65 per spec.
  defp from_components("xyz", components, alpha) do
    from_components("xyz-d65", components, alpha)
  end

  defp from_components("srgb-linear", [r, g, b], alpha) do
    ok(%Color.RGB{
      r: num(r),
      g: num(g),
      b: num(b),
      alpha: alpha_or_nil(alpha),
      working_space: :SRGB
    })
  end

  defp from_components("display-p3", [r, g, b], alpha) do
    ok(%Color.RGB{
      r: num(r),
      g: num(g),
      b: num(b),
      alpha: alpha_or_nil(alpha),
      working_space: :P3
    })
  end

  defp from_components("rec2020", [r, g, b], alpha) do
    ok(%Color.RGB{
      r: num(r),
      g: num(g),
      b: num(b),
      alpha: alpha_or_nil(alpha),
      working_space: :Rec2020
    })
  end

  defp from_components("prophoto-rgb", [r, g, b], alpha) do
    ok(%Color.RGB{
      r: num(r),
      g: num(g),
      b: num(b),
      alpha: alpha_or_nil(alpha),
      working_space: :ProPhoto
    })
  end

  defp from_components(space, components, _alpha) when is_binary(space) do
    {:error,
     %DesignTokensDecodeError{
       reason: :unknown_color_space,
       detail: "#{inspect(space)} with components #{inspect(components)}"
     }}
  end

  # ---- validators --------------------------------------------------------

  defp validate_alpha(nil), do: :ok

  defp validate_alpha(a) when is_number(a) and a >= 0 and a <= 1, do: :ok

  defp validate_alpha(other) do
    {:error, %DesignTokensDecodeError{reason: :bad_alpha, detail: inspect(other)}}
  end

  defp num(n) when is_number(n), do: n * 1.0
  defp num(other), do: other

  defp alpha_or_nil(nil), do: nil
  defp alpha_or_nil(a) when is_number(a), do: a * 1.0

  defp ok(struct), do: {:ok, struct}
end
