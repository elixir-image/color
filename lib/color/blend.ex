defmodule Color.Blend do
  @moduledoc """
  CSS Compositing and Blending Level 1 blend modes.

  `blend/3,4` computes `B(Cb, Cs)` for a source and backdrop colour
  using one of the sixteen standard CSS blend modes. Both inputs are
  interpreted in sRGB and the result is returned as a
  `Color.SRGB` struct.

  Separable blend modes (`:multiply`, `:screen`, `:overlay`,
  `:darken`, `:lighten`, `:color_dodge`, `:color_burn`,
  `:hard_light`, `:soft_light`, `:difference`, `:exclusion`) operate
  per-channel.

  Non-separable modes (`:hue`, `:saturation`, `:color`, `:luminosity`)
  exchange specific colour attributes between source and backdrop and
  are defined in terms of an sRGB luminance and saturation.

  `:normal` simply returns the source.

  ### Examples

      iex> {:ok, c} = Color.Blend.blend("white", "red", :multiply)
      iex> Color.SRGB.to_hex(c)
      "#ff0000"

      iex> {:ok, c} = Color.Blend.blend([0.5, 0.5, 0.5], [0.5, 0.5, 0.5], :screen)
      iex> Color.SRGB.to_hex(c)
      "#bfbfbf"

  """

  @separable [
    :normal,
    :multiply,
    :screen,
    :overlay,
    :darken,
    :lighten,
    :color_dodge,
    :color_burn,
    :hard_light,
    :soft_light,
    :difference,
    :exclusion
  ]

  @nonseparable [:hue, :saturation, :color, :luminosity]

  @doc """
  Blends a source over a backdrop using the given blend mode.

  ### Arguments

  * `backdrop` is the destination colour (`Cb`) — any colour accepted
    by `Color.new/1`.

  * `source` is the source colour (`Cs`) — any colour accepted by
    `Color.new/1`.

  * `mode` is one of `#{inspect(@separable ++ @nonseparable)}`.

  ### Returns

  * `{:ok, %Color.SRGB{}}` on success.

  * `{:error, reason}` if the mode is unknown.

  """
  def blend(backdrop, source, mode) when mode in @separable do
    with {:ok, cb} <- Color.convert(backdrop, Color.SRGB),
         {:ok, cs} <- Color.convert(source, Color.SRGB) do
      {r, g, b} =
        {
          sep(mode, cb.r, cs.r),
          sep(mode, cb.g, cs.g),
          sep(mode, cb.b, cs.b)
        }

      {:ok, %Color.SRGB{r: r, g: g, b: b, alpha: merge_alpha(cb, cs)}}
    end
  end

  def blend(backdrop, source, mode) when mode in @nonseparable do
    with {:ok, cb} <- Color.convert(backdrop, Color.SRGB),
         {:ok, cs} <- Color.convert(source, Color.SRGB) do
      {r, g, b} = nonsep(mode, {cb.r, cb.g, cb.b}, {cs.r, cs.g, cs.b})
      {:ok, %Color.SRGB{r: r, g: g, b: b, alpha: merge_alpha(cb, cs)}}
    end
  end

  def blend(_, _, mode) do
    {:error, "Unknown blend mode #{inspect(mode)}"}
  end

  # ---- separable modes -------------------------------------------------------

  defp sep(:normal, _b, s), do: s
  defp sep(:multiply, b, s), do: b * s
  defp sep(:screen, b, s), do: b + s - b * s

  defp sep(:overlay, b, s), do: sep(:hard_light, s, b)

  defp sep(:darken, b, s), do: min(b, s)
  defp sep(:lighten, b, s), do: max(b, s)

  defp sep(:color_dodge, b, _s) when b == 0, do: 0.0
  defp sep(:color_dodge, _b, s) when s == 1, do: 1.0
  defp sep(:color_dodge, b, s), do: min(1.0, b / (1 - s))

  defp sep(:color_burn, b, _s) when b == 1, do: 1.0
  defp sep(:color_burn, _b, s) when s == 0, do: 0.0
  defp sep(:color_burn, b, s), do: 1 - min(1.0, (1 - b) / s)

  defp sep(:hard_light, b, s) when s <= 0.5, do: sep(:multiply, b, 2 * s)
  defp sep(:hard_light, b, s), do: sep(:screen, b, 2 * s - 1)

  defp sep(:soft_light, b, s) when s <= 0.5 do
    b - (1 - 2 * s) * b * (1 - b)
  end

  defp sep(:soft_light, b, s) do
    d =
      if b <= 0.25 do
        ((16 * b - 12) * b + 4) * b
      else
        :math.sqrt(b)
      end

    b + (2 * s - 1) * (d - b)
  end

  defp sep(:difference, b, s), do: abs(b - s)
  defp sep(:exclusion, b, s), do: b + s - 2 * b * s

  # ---- non-separable modes ---------------------------------------------------

  defp nonsep(:hue, cb, cs), do: set_lum(set_sat(cs, sat(cb)), lum(cb))
  defp nonsep(:saturation, cb, cs), do: set_lum(set_sat(cb, sat(cs)), lum(cb))
  defp nonsep(:color, cb, cs), do: set_lum(cs, lum(cb))
  defp nonsep(:luminosity, cb, cs), do: set_lum(cb, lum(cs))

  # CSS Compositing Level 1 luminance and saturation helpers — all in
  # non-linear sRGB, per the spec.
  defp lum({r, g, b}), do: 0.3 * r + 0.59 * g + 0.11 * b

  defp sat({r, g, b}) do
    max = max(max(r, g), b)
    min = min(min(r, g), b)
    max - min
  end

  defp set_lum({r, g, b}, l) do
    d = l - lum({r, g, b})
    clip_color({r + d, g + d, b + d})
  end

  defp set_sat({r, g, b}, s) do
    {ch_min, ch_mid, ch_max} = min_mid_max({r, g, b})
    {min_name, mid_name, max_name} = min_mid_max_names({r, g, b})

    {new_min, new_mid, new_max} =
      if ch_max > ch_min do
        {0.0, (ch_mid - ch_min) * s / (ch_max - ch_min), s}
      else
        {0.0, 0.0, 0.0}
      end

    assign({min_name, new_min, mid_name, new_mid, max_name, new_max})
  end

  defp clip_color({r, g, b}) do
    l = lum({r, g, b})
    n = min(min(r, g), b)
    x = max(max(r, g), b)

    {r, g, b} =
      if n < 0 do
        {
          l + (r - l) * l / (l - n),
          l + (g - l) * l / (l - n),
          l + (b - l) * l / (l - n)
        }
      else
        {r, g, b}
      end

    if x > 1 do
      {
        l + (r - l) * (1 - l) / (x - l),
        l + (g - l) * (1 - l) / (x - l),
        l + (b - l) * (1 - l) / (x - l)
      }
    else
      {r, g, b}
    end
  end

  defp min_mid_max({r, g, b}) do
    [mn, md, mx] = Enum.sort([r, g, b])
    {mn, md, mx}
  end

  # Returns which channel holds the min / mid / max so we can put the
  # adjusted values back in the right slots.
  defp min_mid_max_names({r, g, b}) do
    sorted =
      [{:r, r}, {:g, g}, {:b, b}]
      |> Enum.sort_by(fn {_, v} -> v end)

    [{min, _}, {mid, _}, {max, _}] = sorted
    {min, mid, max}
  end

  defp assign({min_n, min_v, mid_n, mid_v, max_n, max_v}) do
    vals = %{min_n => min_v, mid_n => mid_v, max_n => max_v}
    {Map.fetch!(vals, :r), Map.fetch!(vals, :g), Map.fetch!(vals, :b)}
  end

  defp merge_alpha(%{alpha: nil}, %{alpha: nil}), do: nil
  defp merge_alpha(%{alpha: a}, %{alpha: nil}), do: a
  defp merge_alpha(%{alpha: nil}, %{alpha: b}), do: b
  defp merge_alpha(%{alpha: _}, %{alpha: b}), do: b
end
