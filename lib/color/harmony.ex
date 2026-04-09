defmodule Color.Harmony do
  @moduledoc """
  Color harmony helpers — rotations and named combinations on the hue
  circle.

  All helpers operate in **Oklch** by default, which gives visually
  consistent rotations across the hue wheel. Pass `:in` to select a
  different cylindrical space (`Color.LCHab`, `Color.LCHuv`,
  `Color.HSL`, `Color.HSV`).

  Every function accepts any color accepted by `Color.new/1` and
  returns a list of `Color.SRGB` structs, ordered starting with the
  input color.

  """

  @doc """
  Rotates a color's hue by `degrees`.

  ### Arguments

  * `color` is any color accepted by `Color.new/1`.

  * `degrees` is the rotation in degrees. Positive is
    counter-clockwise on the hue wheel.

  * `options` is a keyword list.

  ### Options

  * `:in` is the cylindrical color space to rotate in. Defaults to
    `Color.Oklch`.

  ### Returns

  * `{:ok, %Color.SRGB{}}`.

  ### Examples

      iex> {:ok, rotated} = Color.Harmony.rotate_hue("red", 120)
      iex> hex = Color.SRGB.to_hex(rotated)
      iex> String.starts_with?(hex, "#")
      true

  """
  @spec rotate_hue(Color.input(), number(), keyword()) ::
          {:ok, Color.SRGB.t()} | {:error, Exception.t()}
  def rotate_hue(color, degrees, options \\ []) do
    space = Keyword.get(options, :in, Color.Oklch)

    with {:ok, cyl} <- Color.convert(color, space) do
      rotated = do_rotate(space, cyl, degrees)
      Color.convert(rotated, Color.SRGB)
    end
  end

  @doc """
  Returns the two-color complementary pair (`[input, +180°]`).

  ### Arguments

  * `color` is any color accepted by `Color.new/1`.

  * `options` is the same as for `rotate_hue/3`.

  ### Returns

  * `{:ok, [%Color.SRGB{}, %Color.SRGB{}]}`.

  """
  @spec complementary(Color.input(), keyword()) ::
          {:ok, [Color.SRGB.t()]} | {:error, Exception.t()}
  def complementary(color, options \\ []), do: harmonic_set(color, [0, 180], options)

  @doc """
  Returns the three-color analogous set (`[-30°, 0, +30°]`).

  ### Arguments

  * `color` is any color accepted by `Color.new/1`.

  * `options` is the same as for `rotate_hue/3`, plus `:spread`
    (degrees, default `30`).

  ### Returns

  * `{:ok, [%Color.SRGB{}, %Color.SRGB{}, %Color.SRGB{}]}` ordered
    `[anchor, anchor - spread, anchor + spread]`.

  """
  @spec analogous(Color.input(), keyword()) ::
          {:ok, [Color.SRGB.t()]} | {:error, Exception.t()}
  def analogous(color, options \\ []) do
    spread = Keyword.get(options, :spread, 30)
    harmonic_set(color, [0, -spread, spread], options)
  end

  @doc """
  Returns the three-color triadic set (`[0, +120°, +240°]`).

  ### Arguments

  * `color` is any color accepted by `Color.new/1`.

  * `options` is the same as for `rotate_hue/3`.

  ### Returns

  * `{:ok, [%Color.SRGB{}, %Color.SRGB{}, %Color.SRGB{}]}`.

  """
  @spec triadic(Color.input(), keyword()) ::
          {:ok, [Color.SRGB.t()]} | {:error, Exception.t()}
  def triadic(color, options \\ []), do: harmonic_set(color, [0, 120, 240], options)

  @doc """
  Returns the four-color tetradic set (`[0, +90°, +180°, +270°]`).

  ### Arguments

  * `color` is any color accepted by `Color.new/1`.

  * `options` is the same as for `rotate_hue/3`.

  ### Returns

  * `{:ok, [%Color.SRGB{}, %Color.SRGB{}, %Color.SRGB{}, %Color.SRGB{}]}`.

  """
  @spec tetradic(Color.input(), keyword()) ::
          {:ok, [Color.SRGB.t()]} | {:error, Exception.t()}
  def tetradic(color, options \\ []), do: harmonic_set(color, [0, 90, 180, 270], options)

  @doc """
  Returns the three-color split-complementary set
  (`[0, 180 − spread, 180 + spread]`).

  ### Arguments

  * `color` is any color accepted by `Color.new/1`.

  * `options` is the same as for `rotate_hue/3`, plus `:spread`
    (degrees, default `30`).

  ### Returns

  * `{:ok, [%Color.SRGB{}, %Color.SRGB{}, %Color.SRGB{}]}`.

  """
  @spec split_complementary(Color.input(), keyword()) ::
          {:ok, [Color.SRGB.t()]} | {:error, Exception.t()}
  def split_complementary(color, options \\ []) do
    spread = Keyword.get(options, :spread, 30)
    harmonic_set(color, [0, 180 - spread, 180 + spread], options)
  end

  defp harmonic_set(color, degrees_list, options) do
    space = Keyword.get(options, :in, Color.Oklch)

    with {:ok, cyl} <- Color.convert(color, space) do
      colors =
        Enum.map(degrees_list, fn deg ->
          rotated = do_rotate(space, cyl, deg)
          {:ok, srgb} = Color.convert(rotated, Color.SRGB)
          srgb
        end)

      {:ok, colors}
    end
  end

  defp do_rotate(Color.Oklch, c, deg), do: %{c | h: wrap(c.h + deg)}
  defp do_rotate(Color.LCHab, c, deg), do: %{c | h: wrap(c.h + deg)}
  defp do_rotate(Color.LCHuv, c, deg), do: %{c | h: wrap(c.h + deg)}
  defp do_rotate(Color.HSLuv, c, deg), do: %{c | h: wrap(c.h + deg)}
  defp do_rotate(Color.HPLuv, c, deg), do: %{c | h: wrap(c.h + deg)}
  defp do_rotate(Color.HSL, c, deg), do: %{c | h: wrap(c.h * 360 + deg) / 360}
  defp do_rotate(Color.HSV, c, deg), do: %{c | h: wrap(c.h * 360 + deg) / 360}

  defp do_rotate(other, _, _) do
    raise %Color.UnknownColorSpaceError{space: other}
  end

  defp wrap(h) do
    r = :math.fmod(h, 360)
    if r < 0, do: r + 360, else: r
  end
end
