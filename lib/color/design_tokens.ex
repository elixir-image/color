defmodule Color.DesignTokens do
  @moduledoc """
  Encode and decode W3C [Design Tokens Community Group](https://www.designtokens.org/)
  **color** tokens, per the October 2025 draft of the
  [DTCG Color spec](https://www.designtokens.org/tr/2025.10/color/).

  Design tokens are a portable JSON format for design-system
  values. A color token looks like this:

      %{
        "$type" => "color",
        "$value" => %{
          "colorSpace" => "oklch",
          "components" => [0.63, 0.19, 259.5],
          "alpha" => 1.0,
          "hex" => "#3b82f6"
        }
      }

  This module converts between those maps and the library's
  `Color.*` structs, so palettes can round-trip through any tool
  that speaks the DTCG format (Style Dictionary, Figma, Penpot,
  and so on).

  ## Encode

      iex> {:ok, color} = Color.new("#3b82f6")
      iex> token = Color.DesignTokens.encode(color)
      iex> token["colorSpace"]
      "srgb"

  To emit in a different colour space, convert first:

      iex> {:ok, oklch} = Color.convert("#3b82f6", Color.Oklch)
      iex> Color.DesignTokens.encode(oklch) |> Map.get("colorSpace")
      "oklch"

  Or use `encode/2` with the `:space` option — it runs the
  conversion for you:

      iex> token = Color.DesignTokens.encode("#3b82f6", space: Color.Oklch)
      iex> token["colorSpace"]
      "oklch"

  ## Decode

      iex> value = %{"colorSpace" => "oklch", "components" => [0.63, 0.19, 259.5], "alpha" => 1}
      iex> {:ok, oklch} = Color.DesignTokens.decode(value)
      iex> match?(%Color.Oklch{}, oklch)
      true

  Decode also accepts full tokens (with `$type` / `$value`), and
  a hex-only fallback:

      iex> {:ok, srgb} = Color.DesignTokens.decode(%{"hex" => "#3b82f6"})
      iex> Color.to_hex(srgb)
      "#3b82f6"

  Unknown colour spaces or malformed input return
  `{:error, %Color.DesignTokensDecodeError{}}`.

  ## Supported colour spaces

  The DTCG spec and our mapping:

  | DTCG `colorSpace`  | Struct                               |
  |--------------------|--------------------------------------|
  | `"srgb"`           | `Color.SRGB`                         |
  | `"srgb-linear"`    | `Color.RGB` with `working_space: :SRGB`   |
  | `"hsl"`            | `Color.HSL`                          |
  | `"lab"`            | `Color.Lab`                          |
  | `"lch"`            | `Color.LCHab`                        |
  | `"oklab"`          | `Color.Oklab`                        |
  | `"oklch"`          | `Color.Oklch`                        |
  | `"display-p3"`     | `Color.RGB` with `working_space: :P3`     |
  | `"rec2020"`        | `Color.RGB` with `working_space: :Rec2020` |
  | `"prophoto-rgb"`   | `Color.RGB` with `working_space: :ProPhoto` |
  | `"a98-rgb"`        | `Color.AdobeRGB`                     |
  | `"xyz-d50"`        | `Color.XYZ` with `illuminant: :D50`       |
  | `"xyz-d65"` / `"xyz"` | `Color.XYZ` with `illuminant: :D65`    |

  ## Alias tokens

  DTCG supports alias tokens — `"$value" => "{palette.blue.500}"`
  — that reference another token. This module **does not resolve
  aliases**. Resolve them in the caller (where you have the full
  token tree) before passing values here. `decode/1` returns a
  specific `:alias_not_resolved` error if it sees one, so you can
  handle them cleanly.

  """

  alias Color.DesignTokens.Decoder
  alias Color.DesignTokens.Encoder

  @doc """
  Encodes a colour into a DTCG `$value` map.

  ### Arguments

  * `color` is anything accepted by `Color.new/1` or already a
    `Color.*` struct.

  ### Options

  * `:space` is the target colour space for the encoded token —
    any module accepted by `Color.convert/2`. Defaults to the
    colour's current space (no conversion).

  ### Returns

  * A DTCG `$value` map with `"colorSpace"`, `"components"`,
    optional `"alpha"`, and `"hex"` fallback.

  ### Examples

      iex> token = Color.DesignTokens.encode("#3b82f6")
      iex> token["colorSpace"]
      "srgb"

      iex> token = Color.DesignTokens.encode("#3b82f6", space: Color.Oklch)
      iex> token["colorSpace"]
      "oklch"

  """
  @spec encode(Color.input() | struct(), keyword()) :: map()
  def encode(color, options \\ []) do
    struct = ensure_struct!(color)

    target =
      case Keyword.get(options, :space) do
        nil ->
          struct

        space ->
          {:ok, converted} = Color.convert(struct, space)
          converted
      end

    Encoder.encode(target)
  end

  @doc """
  Encodes a colour and wraps it as a full DTCG color token
  (`%{"$type" => "color", "$value" => ...}`).

  ### Arguments

  * `color` is anything accepted by `Color.new/1`.

  ### Options

  See `encode/2`.

  ### Returns

  * A DTCG token map with `$type` and `$value`.

  ### Examples

      iex> token = Color.DesignTokens.encode_token("#3b82f6")
      iex> token["$type"]
      "color"
      iex> token["$value"]["colorSpace"]
      "srgb"

  """
  @spec encode_token(Color.input() | struct(), keyword()) :: map()
  def encode_token(color, options \\ []) do
    %{"$type" => "color", "$value" => encode(color, options)}
  end

  @doc """
  Decodes a DTCG color token (or `$value` map) into a `Color.*`
  struct.

  ### Arguments

  * `token` is either a full token (`%{"$type" => "color", "$value" => ...}`)
    or a bare `$value` map. Alias strings (`"{path.to.token}"`)
    are explicitly rejected — see the module doc.

  ### Returns

  * `{:ok, struct}` on success.

  * `{:error, %Color.DesignTokensDecodeError{}}` on failure.

  ### Examples

      iex> {:ok, oklch} = Color.DesignTokens.decode(%{"colorSpace" => "oklch", "components" => [0.5, 0.1, 180]})
      iex> Float.round(oklch.l, 2)
      0.5

      iex> {:error, %Color.DesignTokensDecodeError{reason: :unknown_color_space}} =
      ...>   Color.DesignTokens.decode(%{"colorSpace" => "fake-space", "components" => [0, 0, 0]})

  """
  @spec decode(map() | binary()) :: {:ok, struct()} | {:error, Exception.t()}
  def decode(token), do: Decoder.decode(token)

  @doc """
  Like `decode/1` but raises on error.

  ### Examples

      iex> Color.DesignTokens.decode!(%{"hex" => "#3b82f6"}) |> Color.to_hex()
      "#3b82f6"

  """
  @spec decode!(map() | binary()) :: struct()
  def decode!(token) do
    case decode(token) do
      {:ok, struct} -> struct
      {:error, e} -> raise e
    end
  end

  # ---- helpers ------------------------------------------------------------

  defp ensure_struct!(struct) when is_struct(struct), do: struct

  defp ensure_struct!(input) do
    case Color.new(input) do
      {:ok, struct} ->
        struct

      {:error, e} ->
        raise ArgumentError,
              "Color.DesignTokens.encode/2 could not parse colour #{inspect(input)}: " <>
                Exception.message(e)
    end
  end
end
