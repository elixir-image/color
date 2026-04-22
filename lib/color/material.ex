defmodule Color.Material do
  @moduledoc """
  A physically-based-rendering (PBR) material wrapper around a
  base colour.

  `%Color.SRGB{}` describes a colour stimulus. `%Color.Material{}`
  describes a *surface* — a colour plus the appearance parameters
  (metallic, roughness, clearcoat) that determine whether the
  surface reads as plastic, painted metal, glossy varnish, or
  matte ceramic. Two materials can share the same base colour yet
  look entirely different because of how light interacts with
  them.

  The parameter set deliberately matches the Disney Principled
  BSDF / glTF 2.0 `pbrMetallicRoughness` convention so values
  from those sources can be imported directly.

  ## Why this exists

  When you sort a palette that mixes plastic swatches with
  polished-metal swatches, any single-axis colour sort puts
  identical base colours next to each other regardless of
  finish — a red plastic and a red-anodized aluminium end up
  visually adjacent even though users file them into different
  mental categories. `Color.Palette.Sort`'s `:material_pbr`
  strategy consumes this struct and produces an ordering that
  respects the metallic-vs-dielectric cliff first, then colour,
  then gloss.

  ## Parameters

  * `:base_color` — a `%Color.SRGB{}` struct. The "albedo" for
    dielectrics or the "specular colour" for metals.

  * `:metallic` — `0.0`–`1.0`. `0.0` is a pure dielectric
    (plastic, paint, wood, skin); `1.0` is a pure conductor
    (gold, copper, aluminium). Values in between model partial
    metallic coatings such as metallic automotive paint.

  * `:roughness` — `0.0`–`1.0`. `0.0` is a perfect mirror;
    `1.0` is a fully diffuse (Lambertian) surface.

  * `:clearcoat` — `0.0`–`1.0`. Strength of an optional
    dielectric varnish layer on top. Defaults to `0.0`
    (no clearcoat).

  * `:clearcoat_roughness` — `0.0`–`1.0`. Roughness of the
    clearcoat layer. Ignored when `:clearcoat` is `0.0`.
    Defaults to `0.03` (near-mirror, matching automotive paint).

  * `:name` — optional string label stored with the material.

  ## Example

      iex> {:ok, red} = Color.new("#ff0000")
      iex> mat = Color.Material.new(red, metallic: 0.0, roughness: 0.85, name: "Matte Red PC")
      iex> mat.name
      "Matte Red PC"
      iex> mat.metallic
      0.0

  """

  @default_metallic 0.0
  @default_roughness 0.5
  @default_clearcoat 0.0
  @default_clearcoat_roughness 0.03

  @valid_keys [:metallic, :roughness, :clearcoat, :clearcoat_roughness, :name]

  defstruct [
    :base_color,
    :name,
    metallic: @default_metallic,
    roughness: @default_roughness,
    clearcoat: @default_clearcoat,
    clearcoat_roughness: @default_clearcoat_roughness
  ]

  @type t :: %__MODULE__{
          base_color: Color.SRGB.t(),
          metallic: float(),
          roughness: float(),
          clearcoat: float(),
          clearcoat_roughness: float(),
          name: binary() | nil
        }

  @doc """
  Builds a `%Color.Material{}` struct.

  ### Arguments

  * `color_input` is anything accepted by `Color.new/1` — a hex
    string, a CSS named colour, an `%Color.SRGB{}` struct, an
    Oklch struct, etc. The input is normalised to `%Color.SRGB{}`
    and stored in `:base_color`.

  ### Options

  * `:metallic` is the metallic parameter in `[0.0, 1.0]`.
    Default `0.0` (dielectric).

  * `:roughness` is the roughness parameter in `[0.0, 1.0]`.
    Default `0.5`.

  * `:clearcoat` is the clearcoat strength in `[0.0, 1.0]`.
    Default `0.0`.

  * `:clearcoat_roughness` is the clearcoat roughness in
    `[0.0, 1.0]`. Default `0.03`.

  * `:name` is an optional string label.

  ### Returns

  * A `%Color.Material{}` struct.

  ### Examples

      iex> mat = Color.Material.new("#c0c0c0", metallic: 1.0, roughness: 0.2)
      iex> mat.metallic
      1.0
      iex> mat.roughness
      0.2

      iex> mat = Color.Material.new("red")
      iex> Color.to_hex(mat.base_color)
      "#ff0000"
      iex> mat.metallic
      0.0

  """
  @spec new(Color.input(), keyword()) :: t()
  def new(color_input, options \\ []) do
    options = validate_options!(options)

    {:ok, srgb} = Color.new(color_input)

    %__MODULE__{
      base_color: srgb,
      metallic: Keyword.fetch!(options, :metallic),
      roughness: Keyword.fetch!(options, :roughness),
      clearcoat: Keyword.fetch!(options, :clearcoat),
      clearcoat_roughness: Keyword.fetch!(options, :clearcoat_roughness),
      name: Keyword.get(options, :name)
    }
  end

  @doc """
  Returns the underlying base colour.

  ### Arguments

  * `material` is a `%Color.Material{}` struct.

  ### Returns

  * A `%Color.SRGB{}` struct.

  ### Examples

      iex> mat = Color.Material.new("#ff0000")
      iex> Color.to_hex(Color.Material.base_color(mat))
      "#ff0000"

  """
  @spec base_color(t()) :: Color.SRGB.t()
  def base_color(%__MODULE__{base_color: color}), do: color

  @doc """
  Returns a tuple suitable for tuple-based sorting.

  The tuple is `{metallic_bucket, hue, lightness, roughness}`
  where `metallic_bucket` is `0` for dielectrics and `1` for
  metals, computed from `metallic >= threshold`.

  Used by `Color.Palette.Sort`'s `:material_pbr` strategy and
  exposed so third parties can compose their own sort keys.

  ### Arguments

  * `material` is a `%Color.Material{}` struct.

  ### Options

  * `:metallic_threshold` is the cutoff between dielectric and
    metallic buckets, in `(0.0, 1.0]`. Default `0.5`.

  ### Returns

  * A `{integer, float, float, float}` tuple.

  ### Examples

      iex> mat = Color.Material.new("#c0c0c0", metallic: 1.0, roughness: 0.2)
      iex> {bucket, _h, _l, rough} = Color.Material.to_pbr_tuple(mat)
      iex> bucket
      1
      iex> rough
      0.2

  """
  @spec to_pbr_tuple(t(), keyword()) ::
          {non_neg_integer(), float(), float(), float()}
  def to_pbr_tuple(%__MODULE__{} = material, options \\ []) do
    threshold = Keyword.get(options, :metallic_threshold, 0.5)

    {:ok, oklch} = Color.convert(material.base_color, Color.Oklch)

    bucket = if material.metallic >= threshold, do: 1, else: 0
    h = oklch.h || 0.0
    l = oklch.l || 0.0

    {bucket, h, l, material.roughness}
  end

  # ---- options validation -------------------------------------------------

  defp validate_options!(options) do
    Enum.each(Keyword.keys(options), fn key ->
      unless key in @valid_keys do
        raise Color.PaletteError,
          reason: :unknown_option,
          detail: "#{inspect(key)} (valid options: #{inspect(@valid_keys)})"
      end
    end)

    options =
      options
      |> Keyword.put_new(:metallic, @default_metallic)
      |> Keyword.put_new(:roughness, @default_roughness)
      |> Keyword.put_new(:clearcoat, @default_clearcoat)
      |> Keyword.put_new(:clearcoat_roughness, @default_clearcoat_roughness)

    check_unit_float!(options, :metallic)
    check_unit_float!(options, :roughness)
    check_unit_float!(options, :clearcoat)
    check_unit_float!(options, :clearcoat_roughness)

    options
  end

  defp check_unit_float!(options, key) do
    value = Keyword.fetch!(options, key)

    unless is_number(value) and value >= 0.0 and value <= 1.0 do
      raise Color.PaletteError,
        reason: :"invalid_#{key}",
        detail: "#{inspect(key)} must be a number in [0.0, 1.0]"
    end
  end
end
