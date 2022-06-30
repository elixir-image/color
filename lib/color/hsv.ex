defmodule Color.Hsv do
  # H, S and L input range = 0 to 1.0

  defstruct [:h, :s, :v, :alpha]

  def to_srgb(%__MODULE__{h: _h, s: 0, v: v, alpha: alpha}) do
    %Color.SRGB{r: v * 255, g: v * 255, b: v * 255, alpha: alpha}
  end

  def to_srgb(%__MODULE__{h: h, s: s, v: v, alpha: alpha}) do
    var_h = h * 6
    var_h = if var_h == 6, do: 0, else: var_h

    var_i = floor(var_h)
    var_1 = v * (1 - s )
    var_2 = v * (1 - s * (var_h - var_i))
    var_3 = v * (1 - s * (1 - (var_h - var_i)))

    {var_r, var_g, var_b} =
      case var_i do
        0 -> {v, var_3, var_1}
        1 -> {var_2, v, var_1}
        2 -> {var_1, v, var_3}
        3 -> {var_1, var_2, v}
        4 -> {var_3, var_1, v}
        _other -> {v, var_1, var_2}
      end

    %Color.SRGB{r: var_r * 255, g: var_g * 255, b: var_b * 255, alpha: alpha}
  end
end