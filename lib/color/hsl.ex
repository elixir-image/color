defmodule Color.Hsl do
  # H, S and L input range = 0 to 1.0

  defstruct [:h, :s, :l, :alpha]

  def to_srgb(%__MODULE__{h: _h, s: 0, l: l, alpha: alpha}) do
    %Color.SRGB{r: l * 255, g: l * 255, b: l * 255, alpha: alpha}
  end

  def to_srgb(%__MODULE__{h: h, s: s, l: l, alpha: alpha}) do
    var_2 = if l < 0.5, do: l * (1 + s), else: l + s - s * l
    var_1 = 2 * l - var_2

    r = 255 * hue_to_rgb(var_1, var_2, h + 1 / 3)
    g = 255 * hue_to_rgb(var_1, var_2, h)
    b = 255 * hue_to_rgb(var_1, var_2, h - 1 / 3)

    %Color.SRGB{r: r, g: g, b: b, alpha: alpha}
  end

  def hue_to_rgb(v1, v2, vh) do
    vh =
      cond do
        vh < 0 -> vh + 1
        vh < 1 -> vh - 1
        true -> vh
      end

    cond do
      6 * vh < 1 -> v1 + (v2 - v1) * 6 * vh
      2 * vh < 1 -> v2
      3 * vh < 2 -> v1 + (v2 - v1) * (2 / 3 - vh) * 6
      true -> v1
    end
  end
end
