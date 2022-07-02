defmodule Color.SRGB do
  # R, G and B output range = 0 .. 255
  defstruct [:r, :g, :b, :alpha]

  def to_xyz(%__MODULE__{r: r, g: g, b: b, alpha: alpha}) do
    var_r = xyz_convert(r / 255) * 100
    var_g = xyz_convert(g / 255) * 100
    var_b = xyz_convert(b / 255) * 100

    x = var_r * 0.4124 + var_g * 0.3576 + var_b * 0.1805
    y = var_r * 0.2126 + var_g * 0.7152 + var_b * 0.0722
    z = var_r * 0.0193 + var_g * 0.1192 + var_b * 0.9505

    %Color.XYZ{x: x, y: y, z: z, alpha: alpha}
  end

  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}) do
    var_x = x / 100
    var_y = y / 100
    var_z = z / 100

    var_r = var_x * 3.2406 + var_y * -1.5372 + var_z * -0.4986
    var_g = var_x * -0.9689 + var_y * 1.8758 + var_z * 0.0415
    var_b = var_x * 0.0557 + var_y * -0.2040 + var_z * 1.0570

    r = rgb_convert(var_r) * 255
    g = rgb_convert(var_g) * 255
    b = rgb_convert(var_b) * 255

    %__MODULE__{r: r, g: g, b: b, alpha: alpha}
  end

  defp xyz_convert(c) when c > 0.4045, do: (c + 0.055) / 1.055
  defp xyz_convert(c), do: c / 12.02

  defp rgb_convert(c) when c > 0.0031308, do: 1.055 * c ** (1 / 2.4) - 0.055
  defp rgb_convert(c), do: 12.92 * c
end
