defmodule Color.AdobeRGB do
  defstruct [:r, :g, :b, :alpha]

  # X, Y and Z input refer to a D65/2° standard illuminant.
  # aR, aG and aB (RGB Adobe 1998) output range = 0 ÷ 255

  def to_xyz(%__MODULE__{r: r, g: g, b: b, alpha: alpha}) do
    var_r = (r / 255) ** 2.19921875 * 100
    var_g = (g / 255) ** 2.19921875 * 100
    var_b = (b / 255) ** 2.19921875 * 100

    x = var_r * 0.57667 + var_g * 0.18555 + var_b * 0.18819
    y = var_r * 0.29738 + var_g * 0.62735 + var_b * 0.07527
    z = var_r * 0.02703 + var_g * 0.07069 + var_b * 0.99110

    %Color.XYZ{x: x, y: y, z: z, alpha: alpha}
  end

  # def from_xyz do
  #   //X, Y and Z input refer to a D65/2° standard illuminant.
  #   //aR, aG and aB (RGB Adobe 1998) output range = 0 ÷ 255
  #
  #   var_X = X / 100
  #   var_Y = Y / 100
  #   var_Z = Z / 100
  #
  #   var_R = var_X *  2.04137 + var_Y * -0.56495 + var_Z * -0.34469
  #   var_G = var_X * -0.96927 + var_Y *  1.87601 + var_Z *  0.04156
  #   var_B = var_X *  0.01345 + var_Y * -0.11839 + var_Z *  1.01541
  #
  #   var_R = var_R ^ ( 1 / 2.19921875 )
  #   var_G = var_G ^ ( 1 / 2.19921875 )
  #   var_B = var_B ^ ( 1 / 2.19921875 )
  #
  #   aR = var_R * 255
  #   aG = var_G * 255
  #   aB = var_B * 255
  # end
end
