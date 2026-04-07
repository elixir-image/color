defmodule Color.YCbCr do
  @moduledoc """
  YCbCr digital-video color space with BT.601, BT.709 and BT.2020
  variants.

  YCbCr operates on **gamma-encoded** RGB (the corresponding
  working-space companded values), not linear RGB. The `:variant`
  field selects the luma coefficients and the matching RGB working
  space / transfer function:

  * `:bt601` — SDTV (ITU-R BT.601). Uses sRGB primaries for the
    underlying RGB.

  * `:bt709` — HDTV (ITU-R BT.709). Uses sRGB primaries (which match
    BT.709 primaries) with the BT.709 transfer function.

  * `:bt2020` — UHDTV (ITU-R BT.2020). Uses BT.2020 primaries and
    transfer function. **Non-constant luminance** variant.

  Channels are normalised full-range floats:

  * `y ∈ [0, 1]` — luma.

  * `cb, cr ∈ [-0.5, 0.5]` — chroma differences.

  If you need the 8-bit TV-range (`Y ∈ [16, 235]`, `Cb/Cr ∈ [16, 240]`)
  values, scale on the outside.

  """

  alias Color.Conversion.Lindbloom

  defstruct [:y, :cb, :cr, :alpha, variant: :bt709]

  # Luma coefficients (Kr, Kg, Kb) for each variant.
  @coefficients %{
    bt601: {0.299, 0.587, 0.114},
    bt709: {0.2126, 0.7152, 0.0722},
    bt2020: {0.2627, 0.6780, 0.0593}
  }

  @doc """
  Converts a YCbCr color to its corresponding gamma-encoded RGB triple.

  The result is a `{r, g, b}` tuple in the working space selected by
  the variant (sRGB for BT.601/BT.709, BT.2020 for :bt2020).

  ### Arguments

  * `ycbcr` is a `Color.YCbCr` struct.

  ### Returns

  * A `{r, g, b}` tuple of unit floats.

  ### Examples

      iex> Color.YCbCr.to_rgb(%Color.YCbCr{y: 1.0, cb: 0.0, cr: 0.0})
      {1.0, 1.0, 1.0}

  """
  def to_rgb(%__MODULE__{y: y, cb: cb, cr: cr, variant: variant}) do
    {kr, kg, kb} = Map.fetch!(@coefficients, variant)

    r = y + 2 * (1 - kr) * cr
    b = y + 2 * (1 - kb) * cb
    g = (y - kr * r - kb * b) / kg
    {r, g, b}
  end

  @doc """
  Converts a gamma-encoded RGB triple to YCbCr.

  ### Arguments

  * `rgb` is a `{r, g, b}` tuple of unit floats in the variant's
    working space.

  * `variant` is `:bt601`, `:bt709` (default) or `:bt2020`.

  ### Returns

  * A `Color.YCbCr` struct.

  """
  def from_rgb({r, g, b}, variant \\ :bt709) do
    {kr, kg, kb} = Map.fetch!(@coefficients, variant)

    y = kr * r + kg * g + kb * b
    cb = (b - y) / (2 * (1 - kb))
    cr = (r - y) / (2 * (1 - kr))

    %__MODULE__{y: y, cb: cb, cr: cr, variant: variant}
  end

  @doc """
  Converts a YCbCr color to CIE `XYZ`.

  For BT.601 and BT.709 the underlying RGB is treated as sRGB. For
  BT.2020 it is linearised with the BT.2020 transfer function and
  converted via the BT.2020 working space.

  ### Arguments

  * `ycbcr` is a `Color.YCbCr` struct.

  ### Returns

  * A `Color.XYZ` struct tagged D65/2°.

  ### Examples

      iex> {:ok, xyz} = Color.YCbCr.to_xyz(%Color.YCbCr{y: 1.0, cb: 0.0, cr: 0.0, variant: :bt709})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4), Float.round(xyz.z, 4)}
      {0.9505, 1.0, 1.0888}

  """
  def to_xyz(%__MODULE__{variant: variant} = ycbcr) do
    {r, g, b} = to_rgb(ycbcr)

    case variant do
      v when v in [:bt601, :bt709] ->
        Color.SRGB.to_xyz(%Color.SRGB{r: r, g: g, b: b, alpha: ycbcr.alpha})

      :bt2020 ->
        linear = {
          Lindbloom.rec2020_inverse_compand(r),
          Lindbloom.rec2020_inverse_compand(g),
          Lindbloom.rec2020_inverse_compand(b)
        }

        Color.RGB.to_xyz(%Color.RGB{
          r: elem(linear, 0),
          g: elem(linear, 1),
          b: elem(linear, 2),
          working_space: :Rec2020,
          alpha: ycbcr.alpha
        })
    end
  end

  @doc """
  Converts a CIE `XYZ` color to YCbCr using the given variant.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct (D65/2°).

  * `variant` is `:bt601`, `:bt709` (default) or `:bt2020`.

  ### Returns

  * A `Color.YCbCr` struct.

  """
  def from_xyz(xyz, variant \\ :bt709)

  def from_xyz(%Color.XYZ{} = xyz, variant) when variant in [:bt601, :bt709] do
    with {:ok, srgb} <- Color.SRGB.from_xyz(xyz) do
      {:ok, from_rgb({srgb.r, srgb.g, srgb.b}, variant) |> put_alpha(srgb.alpha)}
    end
  end

  def from_xyz(%Color.XYZ{} = xyz, :bt2020) do
    with {:ok, rgb} <- Color.RGB.from_xyz(xyz, :Rec2020) do
      encoded = {
        Lindbloom.rec2020_compand(rgb.r),
        Lindbloom.rec2020_compand(rgb.g),
        Lindbloom.rec2020_compand(rgb.b)
      }

      {:ok, from_rgb(encoded, :bt2020) |> put_alpha(rgb.alpha)}
    end
  end

  defp put_alpha(%__MODULE__{} = ycbcr, alpha), do: %{ycbcr | alpha: alpha}
end
