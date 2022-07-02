defmodule Color.RBG.WorkingSpace do

  @rgb_working_space_table """
  # Name    Gamma WP     xr      yr       Yr       xg     yg       Yg        xb      yb      bY

  # http://www.brucelindbloom.com
  Adobe      2.2  D65  0.6400  0.3300  0.297361  0.2100  0.7100  0.627355  0.1500  0.0600  0.075285
  Apple      1.8  D65  0.6250  0.3400  0.244634  0.2800  0.5950  0.672034  0.1550  0.0700  0.083332
  Best       2.2  D50  0.7347  0.2653  0.228457  0.2150  0.7750  0.737352  0.1300  0.0350  0.034191
  Beta       2.2  D50  0.6888  0.3112  0.303273  0.1986  0.7551  0.663786  0.1265  0.0352  0.032941
  Bruce      2.2  D65  0.6400  0.3300  0.240995  0.2800  0.6500  0.683554  0.1500  0.0600  0.075452
  CIE        2.2  E    0.7350  0.2650  0.176204  0.2740  0.7170  0.812985  0.1670  0.0090  0.010811
  ColorMatch 1.8  D50  0.6300  0.3400  0.274884  0.2950  0.6050  0.658132  0.1500  0.0750  0.066985
  Don        2.2  D50  0.6960  0.3000  0.278350  0.2150  0.7650  0.687970  0.1300  0.0350  0.033680
  ECI         L*  D50  0.6700  0.3300  0.320250  0.2100  0.7100  0.602071  0.1400  0.0800  0.077679
  Ekta_Space 2.2  D50  0.6950  0.3050  0.260629  0.2600  0.7000  0.734946  0.1100  0.0050  0.004425
  NTSC       2.2  C    0.6700  0.3300  0.298839  0.2100  0.7100  0.586811  0.1400  0.0800  0.114350
  PAL        2.2  D65  0.6400  0.3300  0.222021  0.2900  0.6000  0.706645  0.1500  0.0600  0.071334
  # SECAM and PAL are the same
  SECAM      2.2  D65  0.6400  0.3300  0.222021  0.2900  0.6000  0.706645  0.1500  0.0600  0.071334
  ProPhoto   1.8  D50  0.7347  0.2653  0.288040  0.1596  0.8404  0.711874  0.0366  0.0001  0.000086
  SMPTE      2.2  D65  0.6300  0.3400  0.212395  0.3100  0.5950  0.701049  0.1550  0.0700  0.086556
  SRGB      ≈2.2  D65  0.6400  0.3300  0.212656  0.3000  0.6000  0.715158  0.1500  0.0600  0.072186
  Wide_Gamut 2.2  D50  0.7350  0.2650  0.258187  0.1150  0.8260  0.724938  0.1570  0.0180  0.016875

  # https://en.wikipedia.org/wiki/DCI-P3
  P3_D65    ≈2.2  D65  0.680   0.320   1.0       0.265   0.690   1.0       0.150   0.060   1.0
  P3_DCI     2.6  DCI  0.680   0.320   1.0       0.265   0.690   1.0       0.150   0.060   1.0
  P3_D60     2.6  D60  0.680   0.320   1.0       0.265   0.690   1.0       0.150   0.060   1.0
  DCI_P3P    2.6  DCI  0.740   0.270   1.0       0.220   0.780   1.0       0.090  -0.090   1.0
  Cinema    ≈2.2  D65  0.740   0.270   1.0       0.170   1.140   1.0       0.080  -0.100   1.0

  # https://en.wikipedia.org/wiki/Rec.1.0709
  Rec709    ≈709  D65  0.64   0.33     1.0       0.30    0.60    1.0       0.15    0.06    1.0

  # https://en.wikipedia.org/wiki/Rec.1.02020
  Rec2020   ≈2020 D65  0.708  0.292    1.0       0.170   0.797   1.0       0.131   0.046   1.0

  # Here we use the following definitions for gamma:
  # ≈2.2   means the sRGB transfer function
  # ≈709   means the Rec709 transfer function
  # ≈2020  means the Rec2020 transfer function

  # Some white point definitions are not standard
  # D60
  # DCI

  """

  @rgb_working_space @rgb_working_space_table
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn line ->
      [working_space, gamma, white_point | data] =
        line
        |> String.split("#")
        |> hd()
        |> String.split("\s", trim: true)
        |> Enum.map(fn elem ->
          case Float.parse(elem) do
            {float, ""} -> float
            :error -> elem
          end
        end)

      data = Enum.chunk_every(data, 3)
      {String.to_atom(working_space), %{gamma: gamma, white_point: white_point, chromaticty: data}}
    end)
    |> Map.new()

  def rgb_working_spaces do
    @rgb_working_space
  end
end