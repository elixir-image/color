defmodule Color.XYZ do
  import Nx.Defn

  defstruct [:x, :y, :z, :alpha, :illuminant, :observer_angle]

  # Calculate the chromatic adaptation matrices that
  # transform XYZ from one illuminant/observer angle to another
  alias Color.{Tristimulus, ChromaticAdaptation}

  adaptations = fn ->
    for source_illuminant <- Tristimulus.illuminants(),
        dest_illuminant <- Tristimulus.illuminants(),
        source_observer_angle <- Tristimulus.observer_angles(),
        dest_observer_angle <- Tristimulus.observer_angles(),
        adaptation_method <- Color.ChromaticAdaptation.adaptation_methods(),
        {source_illuminant, source_observer_angle} != {dest_illuminant, dest_observer_angle} do
      with {:ok, _reference} <- Tristimulus.tristimulus(source_illuminant, source_observer_angle),
           {:ok, _reference} <- Tristimulus.tristimulus(dest_illuminant, dest_observer_angle) do
        matrix =
          ChromaticAdaptation.adaptation_matrix(
            source_illuminant,
            source_observer_angle,
            dest_illuminant,
            dest_observer_angle,
            adaptation_method
          )

        key =
          {source_illuminant, source_observer_angle, dest_illuminant, dest_observer_angle,
           adaptation_method}

        {key, matrix}
      else
        _other ->
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  @chromatic_adaptations adaptations.()

  defn chromatic_adaptations do
    @chromatic_adaptations
  end

  def chromatic_adaptation(
        source_illuminant,
        source_observer_angle,
        dest_illuminant,
        dest_observer_angle,
        adaptation_method
      ) do
    Map.get(
      chromatic_adaptations(),
      {source_illuminant, source_observer_angle, dest_illuminant, dest_observer_angle,
       adaptation_method}
    )
  end
end
