defmodule Color.ChromaticAdaptation do
  alias Color.Tristimulus
  import Nx.Defn

  # http://www.brucelindbloom.com/index.html?Calc.html
  # https://web.stanford.edu/~sujason/ColorBalancing/adaptation.html

  @chromatic_adaptations %{
    xyz_scaling: %{
      matrix:
        [
          [1.0000000, 0.0000000, 0.0000000],
          [0.0000000, 1.0000000, 0.0000000],
          [0.0000000, 0.0000000, 1.0000000]
        ]
        |> Nx.tensor(),
      inverse_matrix:
        [
          [1.0000000, 0.0000000, 0.0000000],
          [0.0000000, 1.0000000, 0.0000000],
          [0.0000000, 0.0000000, 1.0000000]
        ]
        |> Nx.tensor()
    },
    bradford: %{
      matrix:
        [
          [0.8951000, 0.2664000, -0.1614000],
          [-0.7502000, 1.7135000, 0.0367000],
          [0.0389000, -0.0685000, 1.0296000]
        ]
        |> Nx.tensor(),
      inverse_matrix:
        [
          [0.9869929, -0.1470543, 0.1599627],
          [0.4323053, 0.5183603, 0.0492912],
          [-0.0085287, 0.0400428, 0.9684867]
        ]
        |> Nx.tensor()
    },
    von_kries: %{
      matrix:
        [
          [0.4002400, 0.7076000, -0.0808100],
          [-0.2263000, 1.1653200, 0.0457000],
          [0.0000000, 0.0000000, 0.9182200]
        ]
        |> Nx.tensor(),
      inverse_matrix:
        [
          [1.8599364, -1.1293816, 0.2198974],
          [0.3611914, 0.6388125, -0.0000064],
          [0.0000000, 0.0000000, 1.0890636]
        ]
        |> Nx.tensor()
    },
    sharp: %{
      matrix:
        [
          [1.2694, -0.0988, -0.1706],
          [-0.8364, 1.8006, 0.0357],
          [0.0297, -0.0315, 1.0018]
        ]
        |> Nx.tensor(),
      inverse_matrix:
        [
          [0.81563331, 0.04715478, 0.13721663],
          [0.37911438, 0.57694241, 0.04400087],
          [-0.01226014, 0.01674305, 0.99551882]
        ]
        |> Nx.tensor()
    },
    cmccat2000: %{
      matrix:
        [
          [0.7982, 0.3389, -0.1371],
          [-0.5918, 1.5512, 0.0406],
          [0.0008, 0.239, 0.9753]
        ]
        |> Nx.tensor(),
      inverse_matrix:
        [
          [1.0623046159744263, -0.25674277544021606, 0.1600181758403778],
          [0.40792012214660645, 0.5502355694770813, 0.034436870366334915],
          [-0.10083333402872086, -0.13462616503238678, 1.01675546169281]
        ]
        |> Nx.tensor()
    },
    cat02: %{
      matrix:
        [
          [0.7328, 0.4296, -0.1624],
          [-0.7036, 1.6975, 0.0061],
          [0.0030, 0.0136, 0.9834]
        ]
        |> Nx.tensor(),
      inverse_matrix:
        [
          [1.0961238145828247, -0.27886903285980225, 0.18274520337581635],
          [0.45436903834342957, 0.47353315353393555, 0.07209780812263489],
          [-0.009627609513700008, -0.005698031280189753, 1.015325665473938]
        ]
        |> Nx.tensor()
    }
  }

  defn adaptations do
    @chromatic_adaptations
  end

  @adaptation_methods Map.keys(@chromatic_adaptations)

  def adaptation_methods do
    unquote(@adaptation_methods)
  end

  def ργβ(illuminant, observer_angle, adaptation_method \\ :bradford) do
    {:ok, adaptation} = Map.fetch(adaptations(), adaptation_method)
    {:ok, reference} = Tristimulus.tristimulus(illuminant, observer_angle)
    Nx.dot(adaptation.matrix, reference)
  end

  def adaptation_matrix(
        source_illuminant,
        source_observer_angle,
        dest_illuminant,
        dest_observer_angle,
        adaptation_method \\ :bradford
      ) do
    {:ok, adaptation} = Map.fetch(adaptations(), adaptation_method)

    ργβ_source = ργβ(source_illuminant, source_observer_angle, adaptation_method)
    ργβ_destination = ργβ(dest_illuminant, dest_observer_angle, adaptation_method)

    do_adaptation_matrix(ργβ_source, ργβ_destination, adaptation)
  end

  defn do_adaptation_matrix(ργβ_source, ργβ_destination, adaptation) do
    scale_matrix =
      ργβ_destination
      |> Nx.divide(ργβ_source)
      |> Nx.make_diagonal()

    adaptation.inverse_matrix
    |> Nx.dot(scale_matrix)
    |> Nx.dot(adaptation.matrix)
  end
end
