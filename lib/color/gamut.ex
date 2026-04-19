defmodule Color.Gamut do
  @moduledoc """
  Gamut checking and gamut mapping.

  * `in_gamut?/2` — returns whether a color fits inside the given RGB
    working space.

  * `to_gamut/3` — brings an out-of-gamut color into the working
    space. Two methods are provided:

    * `:clip` — clamp linear RGB to `[0, 1]`. Fast and deterministic
      but can visibly distort saturated colors.

    * `:oklch` (default) — the CSS Color 4 gamut-mapping algorithm.
      Converts to Oklch, then binary-searches for the highest chroma
      that still fits inside the destination gamut, preserving
      lightness and hue. This is what browsers do when rendering a
      `color(display-p3 …)` value on an sRGB display.

  ### Examples

      iex> Color.Gamut.in_gamut?(%Color.SRGB{r: 0.5, g: 0.5, b: 0.5}, :SRGB)
      true

      iex> Color.Gamut.in_gamut?(%Color.SRGB{r: 1.2, g: 0.5, b: -0.1}, :SRGB)
      false

  """

  @epsilon 1.0e-5

  @doc """
  Returns `true` if the color lies inside the given RGB working space
  gamut (each linear channel in `[0, 1]` up to a small epsilon).

  ### Arguments

  * `color` is anything accepted by `Color.new/1`.

  * `working_space` is an atom naming an RGB working space (for
    example `:SRGB`, `:P3_D65`, `:Rec2020`). Defaults to `:SRGB`.

  ### Returns

  * A boolean.

  """
  @spec in_gamut?(Color.input(), Color.Types.working_space()) :: boolean()
  def in_gamut?(color, working_space \\ :SRGB) do
    case Color.convert(color, Color.RGB, working_space) do
      {:ok, rgb} ->
        rgb.r >= -@epsilon and rgb.r <= 1 + @epsilon and
          rgb.g >= -@epsilon and rgb.g <= 1 + @epsilon and
          rgb.b >= -@epsilon and rgb.b <= 1 + @epsilon

      _ ->
        false
    end
  end

  @doc """
  Brings a color inside the given RGB working space gamut.

  ### Arguments

  * `color` is anything accepted by `Color.new/1`.

  * `working_space` is an atom naming an RGB working space. Defaults
    to `:SRGB`.

  * `options` is a keyword list.

  ### Options

  * `:method` is `:oklch` (default) or `:clip`.

  ### Returns

  * `{:ok, %Color.SRGB{}}` — for `:SRGB`. For other working spaces the
    result is the appropriate companded RGB struct (`%Color.AdobeRGB{}`
    for `:Adobe`, a linear `%Color.RGB{}` otherwise).

  ### Examples

      iex> {:ok, mapped} = Color.Gamut.to_gamut(%Color.Oklch{l: 0.9, c: 0.3, h: 30.0}, :SRGB)
      iex> Color.Gamut.in_gamut?(mapped, :SRGB)
      true

  """
  @spec to_gamut(Color.input(), Color.Types.working_space(), keyword()) ::
          {:ok, struct()} | {:error, Exception.t()}
  def to_gamut(color, working_space \\ :SRGB, options \\ []) do
    method = Keyword.get(options, :method, :oklch)

    case method do
      :clip ->
        clip(color, working_space)

      :oklch ->
        map_oklch(color, working_space)

      other ->
        {:error, %Color.UnknownGamutMethodError{method: other, valid: [:clip, :oklch]}}
    end
  end

  # ---- methods --------------------------------------------------------------

  defp clip(color, working_space) do
    with {:ok, %Color.RGB{} = rgb} <- Color.convert(color, Color.RGB, working_space) do
      clipped = %{rgb | r: clamp01(rgb.r), g: clamp01(rgb.g), b: clamp01(rgb.b)}
      to_working_space_struct(clipped, working_space)
    end
  end

  defp map_oklch(color, working_space) do
    with {:ok, oklch} <- Color.convert(color, Color.Oklch) do
      cond do
        oklch.l >= 1.0 ->
          finalise_working_space(Color.Oklch, %{oklch | c: 0.0}, working_space)

        oklch.l <= 0.0 ->
          finalise_working_space(Color.Oklch, %{oklch | c: 0.0}, working_space)

        in_gamut_oklch?(oklch, working_space) ->
          finalise_working_space(Color.Oklch, oklch, working_space)

        true ->
          mapped = binary_search_chroma(oklch, working_space)
          finalise_working_space(Color.Oklch, mapped, working_space)
      end
    end
  end

  # CSS Color 4 algorithm: binary search in Oklch chroma, then final
  # clip in linear RGB to resolve remaining out-of-gamut slop (caused
  # by the ΔE stop criterion).
  defp binary_search_chroma(oklch, working_space) do
    jnd = 0.02
    min_c = 0.0
    max_c = oklch.c

    {final, _} = do_search(oklch, min_c, max_c, working_space, jnd, 25)
    final
  end

  defp do_search(oklch, min_c, max_c, working_space, jnd, iters_left) do
    if iters_left <= 0 or max_c - min_c < 1.0e-4 do
      {%{oklch | c: min_c}, max_c}
    else
      mid = (min_c + max_c) / 2
      candidate = %{oklch | c: mid}

      if in_gamut_oklch?(candidate, working_space) do
        do_search(candidate, mid, max_c, working_space, jnd, iters_left - 1)
      else
        # Check whether the clipped version is within JND of the
        # unclipped — if so accept. Otherwise tighten.
        {:ok, %Color.RGB{} = rgb} = Color.convert(candidate, Color.RGB, working_space)
        clipped = %{rgb | r: clamp01(rgb.r), g: clamp01(rgb.g), b: clamp01(rgb.b)}
        {:ok, clipped_oklch} = Color.convert(clipped, Color.Oklch)

        delta = oklab_delta(candidate, clipped_oklch)

        if delta < jnd do
          {%{oklch | c: mid}, mid}
        else
          do_search(oklch, min_c, mid, working_space, jnd, iters_left - 1)
        end
      end
    end
  end

  defp in_gamut_oklch?(oklch, working_space) do
    case Color.convert(oklch, Color.RGB, working_space) do
      {:ok, rgb} ->
        rgb.r >= -@epsilon and rgb.r <= 1 + @epsilon and
          rgb.g >= -@epsilon and rgb.g <= 1 + @epsilon and
          rgb.b >= -@epsilon and rgb.b <= 1 + @epsilon

      _ ->
        false
    end
  end

  defp finalise_working_space(Color.Oklch, oklch, working_space) do
    with {:ok, %Color.RGB{} = rgb} <- Color.convert(oklch, Color.RGB, working_space) do
      clipped = %{rgb | r: clamp01(rgb.r), g: clamp01(rgb.g), b: clamp01(rgb.b)}
      to_working_space_struct(clipped, working_space)
    end
  end

  defp to_working_space_struct(%Color.RGB{} = rgb, :SRGB),
    do: Color.convert(rgb, Color.SRGB)

  defp to_working_space_struct(%Color.RGB{} = rgb, :Adobe),
    do: Color.convert(rgb, Color.AdobeRGB)

  defp to_working_space_struct(%Color.RGB{} = rgb, :Apple),
    do: Color.convert(rgb, Color.AppleRGB)

  defp to_working_space_struct(%Color.RGB{} = rgb, :Rec2020),
    do: Color.convert(rgb, Color.Rec2020)

  defp to_working_space_struct(%Color.RGB{} = rgb, _working_space), do: {:ok, rgb}

  defp oklab_delta(oklch_a, oklch_b) do
    # Convert both to Oklab components for a simple Euclidean ΔE.
    rad_a = oklch_a.h * :math.pi() / 180
    rad_b = oklch_b.h * :math.pi() / 180
    a1 = oklch_a.c * :math.cos(rad_a)
    b1 = oklch_a.c * :math.sin(rad_a)
    a2 = oklch_b.c * :math.cos(rad_b)
    b2 = oklch_b.c * :math.sin(rad_b)

    :math.sqrt(
      :math.pow(oklch_a.l - oklch_b.l, 2) +
        :math.pow(a1 - a2, 2) +
        :math.pow(b1 - b2, 2)
    )
  end

  defp clamp01(v), do: v |> max(0.0) |> min(1.0)
end
