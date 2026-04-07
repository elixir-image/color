defmodule Color.IPT do
  @moduledoc """
  IPT perceptual color space (Ebner & Fairchild, 1998).

  IPT is a Lab-like opponent color space built on D65 and a simple
  non-linearity (`|x|^0.43`). It is the conceptual ancestor of Oklab
  and JzAzBz and is still used for gamut-mapping work because of its
  well-behaved hue linearity.

  """

  alias Color.Conversion.Lindbloom

  defstruct [:i, :p, :t, :alpha]

  # D65 XYZ -> LMS (Hunt-Pointer-Estevez with D65 scaling)
  @m1 [
    [0.4002, 0.7075, -0.0807],
    [-0.2280, 1.1500, 0.0612],
    [0.0000, 0.0000, 0.9184]
  ]

  # LMS' -> IPT
  @m2 [
    [0.4000, 0.4000, 0.2000],
    [4.4550, -4.8510, 0.3960],
    [0.8056, 0.3572, -1.1628]
  ]

  @m1_inv Lindbloom.invert3(@m1)
  @m2_inv Lindbloom.invert3(@m2)

  @doc """
  Converts CIE `XYZ` (D65, `Y ∈ [0, 1]`) to IPT.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct.

  ### Returns

  * A `Color.IPT` struct.

  ### Examples

      iex> {:ok, ipt} = Color.IPT.from_xyz(%Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2})
      iex> {Float.round(ipt.i, 3), abs(ipt.p) < 1.0e-3, abs(ipt.t) < 1.0e-3}
      {1.0, true, true}

  """
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}) do
    lms = Lindbloom.rgb_to_xyz({x, y, z}, @m1)
    lms_p = nonlinear_triple(lms)
    {i, p, t} = Lindbloom.rgb_to_xyz(lms_p, @m2)

    {:ok, %__MODULE__{i: i, p: p, t: t, alpha: alpha}}
  end

  @doc """
  Converts IPT to CIE `XYZ` (D65, `Y ∈ [0, 1]`).

  """
  def to_xyz(%__MODULE__{i: i, p: p, t: t, alpha: alpha}) do
    lms_p = Lindbloom.rgb_to_xyz({i, p, t}, @m2_inv)
    lms = nonlinear_inv_triple(lms_p)
    {x, y, z} = Lindbloom.rgb_to_xyz(lms, @m1_inv)

    {:ok, %Color.XYZ{x: x, y: y, z: z, alpha: alpha, illuminant: :D65, observer_angle: 2}}
  end

  defp nonlinear_triple({a, b, c}), do: {nl(a), nl(b), nl(c)}
  defp nonlinear_inv_triple({a, b, c}), do: {nl_inv(a), nl_inv(b), nl_inv(c)}

  defp nl(v) when v >= 0, do: :math.pow(v, 0.43)
  defp nl(v), do: -:math.pow(-v, 0.43)

  defp nl_inv(v) when v >= 0, do: :math.pow(v, 1 / 0.43)
  defp nl_inv(v), do: -:math.pow(-v, 1 / 0.43)
end
