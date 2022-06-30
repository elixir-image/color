defmodule Color.Lab do
  defstruct [:l, :a, :b, :alpha]

  def to_xyz(%__MODULE__{l: l, a: a, b: b, alpha: alpha}, options \\ []) do
    var_y = (l + 16 ) / 116
    var_x = a / 500 + var_y
    var_z = var_y - b / 200

    [reference_x, reference_y, reference_z] = Color.Tristimulus.reference_white(options)

    x = convert(var_x) * reference_x
    y = convert(var_y) * reference_y
    z = convert(var_z) * reference_z

    %Color.XYZ{x: x, y: y, z: z, alpha: alpha}
  end

  def convert(c) do
    if (c1 = c ** 3) > 0.008856 do
      c1
    else
      (c - 16 / 116 ) / 7.787
    end
  end
end