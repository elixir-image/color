defmodule Color.Mix do
  @moduledoc """
  Color interpolation and gradient generation.

  * `mix/3,4` — linearly interpolate between two colors in a named
    working space. The space matters a lot: mixing red and green in
    sRGB gives muddy brown at `t = 0.5`, while mixing in Oklab gives a
    clean olive. Default is `Color.Oklab`, matching CSS Color 4's
    `color-mix()` recommendation.

  * `gradient/4` — return a list of `n` evenly spaced colors from
    `start` to `stop`, inclusive of both endpoints.

  Both functions accept anything `Color.new/1` accepts and always
  return the mixed color as a `Color.SRGB` struct (so it's ready to
  display). If you need the result in a different space, pipe it
  through `Color.convert/2` afterwards.

  Hue interpolation is handled specially for cylindrical spaces
  (`Color.LCHab`, `Color.LCHuv`, `Color.Oklch`, `Color.HSLuv`,
  `Color.HPLuv`, `Color.HSL`, `Color.HSV`): by default we take the
  **shorter arc** around the hue circle. Pass `hue: :longer`,
  `hue: :increasing` or `hue: :decreasing` to force a different path,
  matching the CSS Color 4 hue-interpolation modes.

  """

  @cylindrical [
    Color.LCHab,
    Color.LCHuv,
    Color.Oklch,
    Color.HSLuv,
    Color.HPLuv,
    Color.HSL,
    Color.HSV
  ]

  @doc """
  Mixes two colors in the given working space.

  ### Arguments

  * `a` is any color accepted by `Color.new/1`.

  * `b` is any color accepted by `Color.new/1`.

  * `t` is the mixing parameter in `[0, 1]`. `0.0` returns `a`,
    `1.0` returns `b`, `0.5` returns the midpoint.

  * `options` is a keyword list.

  ### Options

  * `:in` is the color space module to interpolate in. Defaults to
    `Color.Oklab`.

  * `:hue` is the hue-interpolation mode for cylindrical spaces:
    `:shorter` (default), `:longer`, `:increasing`, `:decreasing`.

  ### Returns

  * A `Color.SRGB` struct.

  ### Examples

      iex> {:ok, mid} = Color.Mix.mix("red", "lime", 0.5)
      iex> hex = Color.SRGB.to_hex(mid) |> String.upcase()
      iex> String.starts_with?(hex, "#")
      true

      iex> {:ok, mid} = Color.Mix.mix("red", "lime", 0.5, in: Color.SRGB)
      iex> Color.SRGB.to_hex(mid) |> String.upcase()
      "#7F8000"

      iex> {:ok, a} = Color.Mix.mix("red", "blue", 0.0)
      iex> {:ok, b} = Color.Mix.mix("red", "blue", 1.0)
      iex> {Color.SRGB.to_hex(a), Color.SRGB.to_hex(b)}
      {"#ff0000", "#0000ff"}

  """
  @spec mix(Color.input(), Color.input(), number(), keyword()) ::
          {:ok, Color.SRGB.t()} | {:error, Exception.t()}
  def mix(a, b, t, options \\ []) when is_number(t) do
    space = Keyword.get(options, :in, Color.Oklab)
    hue_mode = Keyword.get(options, :hue, :shorter)

    with {:ok, ca} <- Color.convert(a, space),
         {:ok, cb} <- Color.convert(b, space) do
      mixed = interpolate(space, ca, cb, t, hue_mode)
      Color.convert(mixed, Color.SRGB)
    end
  end

  @doc """
  Generates an evenly-spaced gradient between `start` and `stop`.

  ### Arguments

  * `start` is any color accepted by `Color.new/1`.

  * `stop` is any color accepted by `Color.new/1`.

  * `steps` is the number of colors to return, `≥ 2`. The first
    result is `start` and the last result is `stop`.

  * `options` is the same as for `mix/4`.

  ### Returns

  * `{:ok, [%Color.SRGB{}, ...]}` with `steps` elements.

  ### Examples

      iex> {:ok, colors} = Color.Mix.gradient("black", "white", 3)
      iex> Enum.map(colors, &Color.SRGB.to_hex/1)
      ["#000000", "#636363", "#ffffff"]

      iex> {:ok, colors} = Color.Mix.gradient("red", "blue", 5)
      iex> length(colors)
      5

  """
  @spec gradient(Color.input(), Color.input(), pos_integer(), keyword()) ::
          {:ok, [Color.SRGB.t()]} | {:error, Exception.t()}
  def gradient(start, stop, steps, options \\ []) when is_integer(steps) and steps >= 2 do
    space = Keyword.get(options, :in, Color.Oklab)
    hue_mode = Keyword.get(options, :hue, :shorter)

    with {:ok, ca} <- Color.convert(start, space),
         {:ok, cb} <- Color.convert(stop, space) do
      colors =
        for i <- 0..(steps - 1) do
          t = i / (steps - 1)
          mixed = interpolate(space, ca, cb, t, hue_mode)
          {:ok, srgb} = Color.convert(mixed, Color.SRGB)
          srgb
        end

      {:ok, colors}
    end
  end

  # ---- interpolation in each supported space ---------------------------------

  defp interpolate(space, a, b, t, hue_mode) when space in @cylindrical do
    cylindrical_interpolate(space, a, b, t, hue_mode)
  end

  defp interpolate(Color.SRGB, a, b, t, _),
    do: %Color.SRGB{
      r: lerp(a.r, b.r, t),
      g: lerp(a.g, b.g, t),
      b: lerp(a.b, b.b, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp interpolate(Color.AdobeRGB, a, b, t, _),
    do: %Color.AdobeRGB{
      r: lerp(a.r, b.r, t),
      g: lerp(a.g, b.g, t),
      b: lerp(a.b, b.b, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp interpolate(Color.XYZ, a, b, t, _),
    do: %Color.XYZ{
      x: lerp(a.x, b.x, t),
      y: lerp(a.y, b.y, t),
      z: lerp(a.z, b.z, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t),
      illuminant: a.illuminant,
      observer_angle: a.observer_angle
    }

  defp interpolate(Color.Lab, a, b, t, _),
    do: %Color.Lab{
      l: lerp(a.l, b.l, t),
      a: lerp(a.a, b.a, t),
      b: lerp(a.b, b.b, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t),
      illuminant: a.illuminant,
      observer_angle: a.observer_angle
    }

  defp interpolate(Color.Luv, a, b, t, _),
    do: %Color.Luv{
      l: lerp(a.l, b.l, t),
      u: lerp(a.u, b.u, t),
      v: lerp(a.v, b.v, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t),
      illuminant: a.illuminant,
      observer_angle: a.observer_angle
    }

  defp interpolate(Color.Oklab, a, b, t, _),
    do: %Color.Oklab{
      l: lerp(a.l, b.l, t),
      a: lerp(a.a, b.a, t),
      b: lerp(a.b, b.b, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp interpolate(Color.IPT, a, b, t, _),
    do: %Color.IPT{
      i: lerp(a.i, b.i, t),
      p: lerp(a.p, b.p, t),
      t: lerp(a.t, b.t, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp interpolate(Color.JzAzBz, a, b, t, _),
    do: %Color.JzAzBz{
      jz: lerp(a.jz, b.jz, t),
      az: lerp(a.az, b.az, t),
      bz: lerp(a.bz, b.bz, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }

  defp interpolate(other, _a, _b, _t, _) do
    raise %Color.UnknownColorSpaceError{space: other}
  end

  defp cylindrical_interpolate(Color.Oklch, a, b, t, hue_mode) do
    %Color.Oklch{
      l: lerp(a.l, b.l, t),
      c: lerp(a.c, b.c, t),
      h: hue_lerp(a.h, b.h, t, hue_mode),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }
  end

  defp cylindrical_interpolate(Color.LCHab, a, b, t, hue_mode) do
    %Color.LCHab{
      l: lerp(a.l, b.l, t),
      c: lerp(a.c, b.c, t),
      h: hue_lerp(a.h, b.h, t, hue_mode),
      alpha: lerp_alpha(a.alpha, b.alpha, t),
      illuminant: a.illuminant,
      observer_angle: a.observer_angle
    }
  end

  defp cylindrical_interpolate(Color.LCHuv, a, b, t, hue_mode) do
    %Color.LCHuv{
      l: lerp(a.l, b.l, t),
      c: lerp(a.c, b.c, t),
      h: hue_lerp(a.h, b.h, t, hue_mode),
      alpha: lerp_alpha(a.alpha, b.alpha, t),
      illuminant: a.illuminant,
      observer_angle: a.observer_angle
    }
  end

  defp cylindrical_interpolate(Color.HSLuv, a, b, t, hue_mode) do
    %Color.HSLuv{
      h: hue_lerp(a.h, b.h, t, hue_mode),
      s: lerp(a.s, b.s, t),
      l: lerp(a.l, b.l, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }
  end

  defp cylindrical_interpolate(Color.HPLuv, a, b, t, hue_mode) do
    %Color.HPLuv{
      h: hue_lerp(a.h, b.h, t, hue_mode),
      s: lerp(a.s, b.s, t),
      l: lerp(a.l, b.l, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }
  end

  defp cylindrical_interpolate(Color.HSL, a, b, t, hue_mode) do
    # Hsl hue is 0..1
    h = hue_lerp(a.h * 360, b.h * 360, t, hue_mode) / 360

    %Color.HSL{
      h: h,
      s: lerp(a.s, b.s, t),
      l: lerp(a.l, b.l, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }
  end

  defp cylindrical_interpolate(Color.HSV, a, b, t, hue_mode) do
    h = hue_lerp(a.h * 360, b.h * 360, t, hue_mode) / 360

    %Color.HSV{
      h: h,
      s: lerp(a.s, b.s, t),
      v: lerp(a.v, b.v, t),
      alpha: lerp_alpha(a.alpha, b.alpha, t)
    }
  end

  # ---- primitives -----------------------------------------------------------

  defp lerp(a, b, t), do: a + (b - a) * t

  defp lerp_alpha(nil, nil, _t), do: nil
  defp lerp_alpha(nil, b, t), do: lerp(1.0, b, t)
  defp lerp_alpha(a, nil, t), do: lerp(a, 1.0, t)
  defp lerp_alpha(a, b, t), do: lerp(a, b, t)

  # Hue interpolation following CSS Color 4 semantics. Hues are in
  # degrees on `[0, 360)`; output is in the same range.
  defp hue_lerp(h1, h2, t, mode) do
    h1 = wrap_360(h1)
    h2 = wrap_360(h2)

    {h1, h2} =
      case mode do
        :shorter ->
          diff = h2 - h1

          cond do
            diff > 180 -> {h1 + 360, h2}
            diff < -180 -> {h1, h2 + 360}
            true -> {h1, h2}
          end

        :longer ->
          diff = h2 - h1

          cond do
            0 < diff and diff < 180 -> {h1 + 360, h2}
            -180 < diff and diff <= 0 -> {h1, h2 + 360}
            true -> {h1, h2}
          end

        :increasing ->
          if h2 < h1, do: {h1, h2 + 360}, else: {h1, h2}

        :decreasing ->
          if h1 < h2, do: {h1 + 360, h2}, else: {h1, h2}
      end

    wrap_360(lerp(h1, h2, t))
  end

  defp wrap_360(h) do
    r = :math.fmod(h, 360)
    if r < 0, do: r + 360, else: r
  end
end
