defmodule Color do
  @moduledoc """
  Top-level color conversion dispatch.

  Every color struct in this library implements `to_xyz/1` and
  `from_xyz/1`. `convert/2` and `convert/3` use `Color.XYZ` as the hub:
  any source color is converted to `XYZ`, then converted to the
  requested target color.

  The color spaces currently supported are:

  * `Color.XYZ` — CIE 1931 tristimulus.

  * `Color.XYY` — CIE xyY (chromaticity + luminance).

  * `Color.Lab` — CIE 1976 `L*a*b*`.

  * `Color.LCHab` — cylindrical `L*a*b*`.

  * `Color.Luv` — CIE 1976 `L*u*v*`.

  * `Color.LCHuv` — cylindrical `L*u*v*`.

  * `Color.Oklab` — Oklab perceptual color space (Björn Ottosson, 2020),
    defined against D65.

  * `Color.Oklch` — cylindrical Oklab.

  * `Color.HSLuv` / `Color.HPLuv` — perceptually-uniform HSL variants
    built on CIELUV (Boronine 2015).

  * `Color.JzAzBz` — HDR/wide-gamut perceptual space (Safdar et al. 2017).

  * `Color.ICtCp` — Rec. 2100 HDR (PQ or HLG).

  * `Color.IPT` — Ebner & Fairchild 1998, ancestor of Oklab.

  * `Color.CAM16UCS` — CAM16 Color Appearance Model uniform space.

  * `Color.CMYK` — simple subtractive (no ICC).

  * `Color.YCbCr` — digital video with BT.601/709/2020 variants.

  * `Color.SRGB` — companded sRGB working space (D65).

  * `Color.AdobeRGB` — companded Adobe RGB (1998) working space (D65).

  * `Color.RGB` — linear RGB in any named working space.

  * `Color.Hsl`, `Color.Hsv` — non-linear reparameterisations of sRGB.

  All struct modules also expose their own `to_xyz/1` and `from_xyz/1`
  functions directly if you want to skip dispatch.

  ## Building colors with `new/1`

  `new/1` accepts any of:

  * A color struct (passed through unchanged).

  * A hex string (`"#ff0000"`, `"#f80"`, `"#ff000080"`, with or without
    the leading `#`) or a CSS named color (`"rebeccapurple"`).

  * A bare list `[r, g, b]` or `[r, g, b, a]` of unit-range floats,
    which is interpreted as **sRGB**.

  `convert/2` and `convert/3` accept the same inputs, so you can write
  `Color.convert([1.0, 0.0, 0.0], Color.Lab)` without first wrapping
  the list in an `SRGB` struct.

  ## Alpha

  Every color struct has an `:alpha` field. Alpha is passed straight
  through every conversion — it is never touched by the color math
  itself. The library's API assumes **straight** (unassociated) alpha.
  If you are working with pre-multiplied pixel data, un-premultiply
  before converting (see the "Pre-multiplied alpha" section below and
  `Color.unpremultiply/1` / `Color.premultiply/1`) and re-multiply
  afterwards.

  ## Pre-multiplied alpha

  Pre-multiplied alpha matters only when a color space's transfer
  function is **non-linear** with respect to the RGB channels. In a
  pre-multiplied pixel `(R·a, G·a, B·a, a)`, the stored channels are
  no longer the pixel's true color — they are the color scaled by its
  own coverage. Applying a non-linear operation like sRGB companding
  to `R·a` does not give you `sRGB(R)·a` because
  `(R·a)^γ ≠ R^γ · a^γ`.

  Since this library's forward pipeline is always
  `source → linear RGB → XYZ → target`, and several stages contain
  non-linear steps (sRGB companding, Adobe RGB gamma, the PQ / HLG
  transfer functions, Lab's `f(x)`, Oklab's cube root, CAM16's
  post-adaptation compression, etc.), converting a pre-multiplied
  color directly is **incorrect** and will produce subtly wrong
  output.

  The rule is:

  1. If your color is straight-alpha: just call `convert/2`. The alpha
     value is carried through untouched.

  2. If your color is pre-multiplied: call `Color.unpremultiply/1`,
     then `convert/2`, then `Color.premultiply/1` on the result if you
     still need pre-multiplied output.

  `premultiply/1` and `unpremultiply/1` are only defined for
  `Color.SRGB`, `Color.AdobeRGB` and `Color.RGB` (linear), since
  pre-multiplication is only meaningful in spaces with an RGB tuple.

  """

  @xyz_hub [
    Color.XYZ,
    Color.XYY,
    Color.Lab,
    Color.LCHab,
    Color.Luv,
    Color.LCHuv,
    Color.Oklab,
    Color.Oklch,
    Color.SRGB,
    Color.AdobeRGB,
    Color.Hsl,
    Color.Hsv,
    Color.HSLuv,
    Color.HPLuv,
    Color.CMYK,
    Color.YCbCr,
    Color.JzAzBz,
    Color.ICtCp,
    Color.IPT,
    Color.CAM16UCS
  ]

  # Targets that require a specific reference white. Any source XYZ with
  # a different illuminant is chromatically adapted (Bradford) before
  # being passed to the target's from_xyz/1.
  @fixed_illuminant %{
    Color.SRGB => {:D65, 2},
    Color.AdobeRGB => {:D65, 2},
    Color.Oklab => {:D65, 2},
    Color.Oklch => {:D65, 2},
    Color.Hsl => {:D65, 2},
    Color.Hsv => {:D65, 2},
    Color.HSLuv => {:D65, 2},
    Color.HPLuv => {:D65, 2},
    Color.CMYK => {:D65, 2},
    Color.YCbCr => {:D65, 2},
    Color.JzAzBz => {:D65, 2},
    Color.ICtCp => {:D65, 2},
    Color.IPT => {:D65, 2},
    Color.CAM16UCS => {:D65, 2}
  }

  @doc """
  Builds a color struct from a variety of inputs.

  ### Arguments

  * `input` is one of:

    * A color struct — returned unchanged inside `{:ok, struct}`.

    * A bare list of three unit-range floats `[r, g, b]`, interpreted
      as **sRGB** and returned as `%Color.SRGB{}`.

    * A bare list of four unit-range floats `[r, g, b, a]`, interpreted
      as **sRGB** with straight alpha.

    * A hex string (`"#ff0000"`, `"#ff000080"`, `"#f80"`, or the same
      without the leading `#`).

    * A CSS named color string (`"rebeccapurple"`, `"red"`).

  ### Returns

  * `{:ok, struct}`.

  * `{:error, reason}` if the input can't be interpreted.

  ### Examples

      iex> {:ok, c} = Color.new([1.0, 0.5, 0.0])
      iex> {c.r, c.g, c.b, c.alpha}
      {1.0, 0.5, 0.0, nil}

      iex> {:ok, c} = Color.new([1.0, 0.0, 0.0, 0.75])
      iex> c.alpha
      0.75

      iex> {:ok, c} = Color.new("#ff0000")
      iex> c.r
      1.0

      iex> {:ok, c} = Color.new("rebeccapurple")
      iex> {Float.round(c.r, 4), Float.round(c.g, 4), Float.round(c.b, 4)}
      {0.4, 0.2, 0.6}

  """
  def new([r, g, b]) when is_number(r) and is_number(g) and is_number(b) do
    {:ok, %Color.SRGB{r: r * 1.0, g: g * 1.0, b: b * 1.0}}
  end

  def new([r, g, b, a])
      when is_number(r) and is_number(g) and is_number(b) and is_number(a) do
    {:ok, %Color.SRGB{r: r * 1.0, g: g * 1.0, b: b * 1.0, alpha: a * 1.0}}
  end

  def new(string) when is_binary(string) do
    Color.SRGB.parse(string)
  end

  def new(%struct{} = color) do
    if struct in @xyz_hub or struct == Color.RGB do
      {:ok, color}
    else
      {:error, "Unsupported color struct #{inspect(struct)}"}
    end
  end

  def new(other) do
    {:error, "Cannot build a color from #{inspect(other)}"}
  end

  @doc """
  Converts a color to a different color space.

  `color` may be anything accepted by `new/1`, including a bare list
  `[r, g, b]` or `[r, g, b, a]` (interpreted as sRGB), a hex string, a
  CSS named color, or a color struct.

  For `Color.RGB` (linear, any working space) use `convert/3` and pass
  the working-space atom as the third argument.

  ### Arguments

  * `color` is any input accepted by `new/1`.

  * `target` is the target module (for example `Color.Lab`, `Color.SRGB`).

  ### Returns

  * `{:ok, %target{}}` on success.

  * `{:error, reason}` if the conversion can't be performed.

  ### Examples

      iex> {:ok, lab} = Color.convert(%Color.SRGB{r: 1.0, g: 0.0, b: 0.0}, Color.Lab)
      iex> {Float.round(lab.l, 2), Float.round(lab.a, 2), Float.round(lab.b, 2)}
      {53.24, 80.09, 67.2}

      iex> {:ok, lab} = Color.convert([1.0, 0.0, 0.0], Color.Lab)
      iex> Float.round(lab.l, 2)
      53.24

      iex> {:ok, srgb} = Color.convert("#ff0000", Color.SRGB)
      iex> {Float.round(srgb.r, 6), Float.round(srgb.g, 6), Float.round(srgb.b, 6)}
      {1.0, 0.0, 0.0}

      iex> {:ok, srgb} = Color.convert(%Color.Lab{l: 53.2408, a: 80.0925, b: 67.2032}, Color.SRGB)
      iex> {Float.round(srgb.r, 3), Float.round(srgb.g, 3), Float.round(srgb.b, 3)}
      {1.0, 0.0, 0.0}

      iex> {:ok, c} = Color.convert([1.0, 0.0, 0.0, 0.5], Color.Lab)
      iex> c.alpha
      0.5

  """
  def convert(color, target) when target in @xyz_hub do
    with {:ok, color} <- new(color),
         {:ok, xyz} <- to_xyz(color),
         {:ok, xyz} <- adapt_for(xyz, target) do
      target.from_xyz(xyz)
    end
  end

  def convert(_color, Color.RGB) do
    {:error,
     "Color.RGB needs a working space. Use convert/3 with the " <>
       "working_space atom as the third argument."}
  end

  def convert(_color, target) do
    {:error, "Unsupported target color module #{inspect(target)}"}
  end

  @doc """
  Converts a color to `Color.RGB` (linear) in the given working space.

  ### Arguments

  * `color` is any supported color struct.

  * `target` must be `Color.RGB`.

  * `working_space` is an atom naming an RGB working space (for example
    `:SRGB`, `:Adobe`, `:ProPhoto`).

  ### Returns

  * `{:ok, %Color.RGB{}}` on success.

  ### Examples

      iex> {:ok, rgb} = Color.convert(%Color.SRGB{r: 1.0, g: 1.0, b: 1.0}, Color.RGB, :SRGB)
      iex> {Float.round(rgb.r, 3), Float.round(rgb.g, 3), Float.round(rgb.b, 3)}
      {1.0, 1.0, 1.0}

  """
  def convert(color, Color.RGB, working_space) do
    with {:ok, info} <- Color.RGB.WorkingSpace.rgb_conversion_matrix(working_space),
         {:ok, color} <- new(color),
         {:ok, xyz} <- to_xyz(color),
         {:ok, xyz} <-
           Color.XYZ.adapt(xyz, info.illuminant, observer_angle: info.observer_angle) do
      Color.RGB.from_xyz(xyz, working_space)
    end
  end

  defp adapt_for(%Color.XYZ{} = xyz, target) do
    case Map.get(@fixed_illuminant, target) do
      nil ->
        {:ok, xyz}

      {ill, obs} ->
        Color.XYZ.adapt(xyz, ill, observer_angle: obs)
    end
  end

  @doc """
  Converts any supported color to `Color.XYZ`.

  ### Arguments

  * `color` is any supported color struct.

  ### Returns

  * `{:ok, %Color.XYZ{}}`.

  """
  def to_xyz(%Color.XYZ{} = xyz), do: {:ok, xyz}
  def to_xyz(%Color.XYY{} = c), do: Color.XYY.to_xyz(c)
  def to_xyz(%Color.Lab{} = c), do: Color.Lab.to_xyz(c)
  def to_xyz(%Color.LCHab{} = c), do: Color.LCHab.to_xyz(c)
  def to_xyz(%Color.Luv{} = c), do: Color.Luv.to_xyz(c)
  def to_xyz(%Color.LCHuv{} = c), do: Color.LCHuv.to_xyz(c)
  def to_xyz(%Color.Oklab{} = c), do: Color.Oklab.to_xyz(c)
  def to_xyz(%Color.Oklch{} = c), do: Color.Oklch.to_xyz(c)
  def to_xyz(%Color.HSLuv{} = c), do: Color.HSLuv.to_xyz(c)
  def to_xyz(%Color.HPLuv{} = c), do: Color.HPLuv.to_xyz(c)
  def to_xyz(%Color.CMYK{} = c), do: Color.CMYK.to_xyz(c)
  def to_xyz(%Color.YCbCr{} = c), do: Color.YCbCr.to_xyz(c)
  def to_xyz(%Color.JzAzBz{} = c), do: Color.JzAzBz.to_xyz(c)
  def to_xyz(%Color.ICtCp{} = c), do: Color.ICtCp.to_xyz(c)
  def to_xyz(%Color.IPT{} = c), do: Color.IPT.to_xyz(c)
  def to_xyz(%Color.CAM16UCS{} = c), do: Color.CAM16UCS.to_xyz(c)
  def to_xyz(%Color.SRGB{} = c), do: Color.SRGB.to_xyz(c)
  def to_xyz(%Color.AdobeRGB{} = c), do: Color.AdobeRGB.to_xyz(c)
  def to_xyz(%Color.RGB{} = c), do: Color.RGB.to_xyz(c)
  def to_xyz(%Color.Hsl{} = c), do: Color.Hsl.to_xyz(c)
  def to_xyz(%Color.Hsv{} = c), do: Color.Hsv.to_xyz(c)

  @doc """
  Pre-multiplies a color's channels by its alpha.

  Only supported for RGB-tuple color spaces (`Color.SRGB`,
  `Color.AdobeRGB`, `Color.RGB`) since pre-multiplication is not
  meaningful for opponent or cylindrical spaces. A color with `nil`
  alpha is treated as fully opaque (`alpha = 1.0`) and is returned
  unchanged.

  ### Arguments

  * `color` is an RGB-tuple color struct.

  ### Returns

  * A new color struct of the same type with pre-multiplied channels.

  ### Examples

      iex> Color.premultiply(%Color.SRGB{r: 1.0, g: 0.5, b: 0.25, alpha: 0.5})
      %Color.SRGB{r: 0.5, g: 0.25, b: 0.125, alpha: 0.5}

      iex> Color.premultiply(%Color.SRGB{r: 1.0, g: 0.5, b: 0.25})
      %Color.SRGB{r: 1.0, g: 0.5, b: 0.25, alpha: nil}

  """
  def premultiply(%Color.SRGB{alpha: nil} = c), do: c
  def premultiply(%Color.SRGB{alpha: a} = c), do: %{c | r: c.r * a, g: c.g * a, b: c.b * a}

  def premultiply(%Color.AdobeRGB{alpha: nil} = c), do: c
  def premultiply(%Color.AdobeRGB{alpha: a} = c), do: %{c | r: c.r * a, g: c.g * a, b: c.b * a}

  def premultiply(%Color.RGB{alpha: nil} = c), do: c
  def premultiply(%Color.RGB{alpha: a} = c), do: %{c | r: c.r * a, g: c.g * a, b: c.b * a}

  def premultiply(%struct{}) do
    raise ArgumentError,
          "premultiply/1 is only supported for Color.SRGB, Color.AdobeRGB and " <>
            "Color.RGB (linear). Got #{inspect(struct)}."
  end

  @doc """
  Inverts `premultiply/1`. A color with `nil` alpha is returned
  unchanged; a color with `alpha = 0.0` is returned unchanged (the
  original channels are unrecoverable and the alpha is authoritative).

  ### Arguments

  * `color` is an RGB-tuple color struct.

  ### Returns

  * A new color struct of the same type with un-pre-multiplied channels.

  ### Examples

      iex> Color.unpremultiply(%Color.SRGB{r: 0.5, g: 0.25, b: 0.125, alpha: 0.5})
      %Color.SRGB{r: 1.0, g: 0.5, b: 0.25, alpha: 0.5}

      iex> Color.unpremultiply(%Color.SRGB{r: 0.0, g: 0.0, b: 0.0, alpha: 0.0})
      %Color.SRGB{r: 0.0, g: 0.0, b: 0.0, alpha: 0.0}

  """
  def unpremultiply(%Color.SRGB{alpha: nil} = c), do: c
  def unpremultiply(%Color.SRGB{alpha: a} = c) when a == 0, do: c
  def unpremultiply(%Color.SRGB{alpha: a} = c), do: %{c | r: c.r / a, g: c.g / a, b: c.b / a}

  def unpremultiply(%Color.AdobeRGB{alpha: nil} = c), do: c
  def unpremultiply(%Color.AdobeRGB{alpha: a} = c) when a == 0, do: c
  def unpremultiply(%Color.AdobeRGB{alpha: a} = c),
    do: %{c | r: c.r / a, g: c.g / a, b: c.b / a}

  def unpremultiply(%Color.RGB{alpha: nil} = c), do: c
  def unpremultiply(%Color.RGB{alpha: a} = c) when a == 0, do: c
  def unpremultiply(%Color.RGB{alpha: a} = c), do: %{c | r: c.r / a, g: c.g / a, b: c.b / a}

  def unpremultiply(%struct{}) do
    raise ArgumentError,
          "unpremultiply/1 is only supported for Color.SRGB, Color.AdobeRGB and " <>
            "Color.RGB (linear). Got #{inspect(struct)}."
  end
end
