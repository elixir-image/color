defmodule Color.XYZ do
  defstruct [:x, :y, :z, :alpha, :illuminant, :observer_angle]

  # Calculate the chromatic adaptation matrices that
  # transform XYZ from one illuminant/observer angle to another
  alias Color.{Tristimulus, ChromaticAdaptation}

  for source_illuminant <- Tristimulus.illuminants(),
      dest_illuminant <- Tristimulus.illuminants(),
      source_observer_angle <- Tristimulus.observer_angles(),
      dest_observer_angle <- Tristimulus.observer_angles(),
      adaptation_method <- Color.ChromaticAdaptation.methods(),
      {source_illuminant, source_observer_angle} != {dest_illuminant, dest_observer_angle} do

    matrix =
      ChromaticAdaptation.adaptation_matrix(source_illuminant, source_observer_angle, dest_illuminant, dest_observer_angle, adaptation_method)

    def chromatic_adaptation(
        unquote(source_illuminant),
        unquote(source_observer_angle),
        unquote(dest_illuminant),
        unquote(dest_observer_angle),
        unquote(adaptation_method)) do
      unquote(Macro.escape(matrix))
    end
  end
end