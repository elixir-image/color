defmodule Color.ChromaticAdaptation do
  @moduledoc """
  Chromatic adaptation transforms between reference whites.

  Supported methods: `:xyz_scaling`, `:bradford` (default), `:von_kries`,
  `:sharp`, `:cmccat2000`, `:cat02`. Matrices are from Bruce Lindbloom
  (http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html) and
  the CAT02 / CMCCAT2000 literature.

  All math is done with plain Elixir lists and floats; no `Nx`
  dependency is required. Adaptation matrices are computed lazily and
  memoised in `:persistent_term`.

  """

  alias Color.Tristimulus
  alias Color.Conversion.Lindbloom

  @chromatic_adaptations %{
    xyz_scaling: %{
      matrix: [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0]
      ],
      inverse_matrix: [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0]
      ]
    },
    bradford: %{
      matrix: [
        [0.8951000, 0.2664000, -0.1614000],
        [-0.7502000, 1.7135000, 0.0367000],
        [0.0389000, -0.0685000, 1.0296000]
      ],
      inverse_matrix: [
        [0.9869929, -0.1470543, 0.1599627],
        [0.4323053, 0.5183603, 0.0492912],
        [-0.0085287, 0.0400428, 0.9684867]
      ]
    },
    von_kries: %{
      matrix: [
        [0.4002400, 0.7076000, -0.0808100],
        [-0.2263000, 1.1653200, 0.0457000],
        [0.0000000, 0.0000000, 0.9182200]
      ],
      inverse_matrix: [
        [1.8599364, -1.1293816, 0.2198974],
        [0.3611914, 0.6388125, -0.0000064],
        [0.0000000, 0.0000000, 1.0890636]
      ]
    },
    sharp: %{
      matrix: [
        [1.2694, -0.0988, -0.1706],
        [-0.8364, 1.8006, 0.0357],
        [0.0297, -0.0315, 1.0018]
      ],
      inverse_matrix: [
        [0.81563331, 0.04715478, 0.13721663],
        [0.37911438, 0.57694241, 0.04400087],
        [-0.01226014, 0.01674305, 0.99551882]
      ]
    },
    cmccat2000: %{
      matrix: [
        [0.7982, 0.3389, -0.1371],
        [-0.5918, 1.5512, 0.0406],
        [0.0008, 0.239, 0.9753]
      ],
      inverse_matrix: [
        [1.0623046159744263, -0.25674277544021606, 0.1600181758403778],
        [0.40792012214660645, 0.5502355694770813, 0.034436870366334915],
        [-0.10083333402872086, -0.13462616503238678, 1.01675546169281]
      ]
    },
    cat02: %{
      matrix: [
        [0.7328, 0.4296, -0.1624],
        [-0.7036, 1.6975, 0.0061],
        [0.0030, 0.0136, 0.9834]
      ],
      inverse_matrix: [
        [1.0961238145828247, -0.27886903285980225, 0.18274520337581635],
        [0.45436903834342957, 0.47353315353393555, 0.07209780812263489],
        [-0.009627609513700008, -0.005698031280189753, 1.015325665473938]
      ]
    }
  }

  def adaptations, do: @chromatic_adaptations

  @adaptation_methods Map.keys(@chromatic_adaptations)

  def adaptation_methods, do: @adaptation_methods

  @doc """
  Returns the `(ρ, γ, β)` cone response of a reference white under the
  given adaptation method.

  ### Arguments

  * `illuminant` is the illuminant atom.

  * `observer_angle` is `2` or `10`.

  * `adaptation_method` defaults to `:bradford`.

  ### Returns

  * A `{ρ, γ, β}` tuple.

  """
  def ργβ(illuminant, observer_angle, adaptation_method \\ :bradford) do
    adaptation = Map.fetch!(@chromatic_adaptations, adaptation_method)

    [xr, yr, zr] =
      Tristimulus.reference_white(illuminant: illuminant, observer_angle: observer_angle)

    Lindbloom.rgb_to_xyz({xr, yr, zr}, adaptation.matrix)
  end

  @doc """
  Returns the 3x3 chromatic adaptation matrix as a list of rows.

  ### Arguments

  * `source_illuminant` is the source reference white atom.

  * `source_observer_angle` is `2` or `10`.

  * `dest_illuminant` is the destination reference white atom.

  * `dest_observer_angle` is `2` or `10`.

  * `adaptation_method` defaults to `:bradford`.

  ### Returns

  * A list of three three-element rows.

  ### Examples

      iex> m = Color.ChromaticAdaptation.adaptation_matrix_list(:D50, 2, :D65, 2)
      iex> [[a, _, _] | _] = m
      iex> Float.round(a, 4)
      0.9556

  """
  def adaptation_matrix_list(
        source_illuminant,
        source_observer_angle,
        dest_illuminant,
        dest_observer_angle,
        adaptation_method \\ :bradford
      ) do
    adaptation = Map.fetch!(@chromatic_adaptations, adaptation_method)

    {rs, gs, bs} = ργβ(source_illuminant, source_observer_angle, adaptation_method)
    {rd, gd, bd} = ργβ(dest_illuminant, dest_observer_angle, adaptation_method)

    scale = [
      [rd / rs, 0.0, 0.0],
      [0.0, gd / gs, 0.0],
      [0.0, 0.0, bd / bs]
    ]

    adaptation.inverse_matrix
    |> Lindbloom.matmul3(scale)
    |> Lindbloom.matmul3(adaptation.matrix)
  end
end
