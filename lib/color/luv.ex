defmodule Color.Luv do
  defstruct [:l, :u, :v, :alpha]

  def to_xyz(%__MODULE__{l: l, u: u, v: v, alpha: alpha}, options \\ []) do
    [reference_x, reference_y, reference_z] = Color.Tristimulus.reference_white(options)

    var_y = (l + 16 ) / 116
    var_y = if (y_cubed = var_y ** 3) > 0.008856, do: y_cubed, else: (var_y - 16 / 116 ) / 7.787

    ref_u = (4 * reference_x) / (reference_x + (15 * reference_y) + (3 * reference_z))
    ref_v = (9 * reference_y) / (reference_x + (15 * reference_y) + (3 * reference_z))

    var_u = u / (13 * l) + ref_u
    var_v = v / (13 * l) + ref_v

    y = var_y * 100
    x =  -(9 * y * var_u) / ((var_u - 4) * var_v - var_u * var_v)
    z = (9 * y - (15 * var_v * y) - (var_v * x)) / (3 * var_v)

    %Color.XYZ{x: x, y: y, z: z, alpha: alpha}
  end
end