defmodule Color.Tristimulus do
  import Nx.Defn

  @doc false

  # https://www.easyrgb.com/en/math.php

  @observer_angles [2, 10]

  def observer_angles do
    @observer_angles
  end

  def reference_white(options \\ []) when is_list(options) do
    illuminant = Keyword.get(options, :illuminant, :D65)
    observer_angle = Keyword.get(options, :observer_angle, 2)

    case tristimulus(illuminant, observer_angle) do
      {:ok, data} -> data
      {:error, reason} -> raise ArgumentError, message: reason
    end
  end

  @xyz_tristimulus_table """
  #          2° (CIE 1931)    10° (CIE 1964)
  # Illuminant x2      y2      x10      y10    CCT     Description
  A        0.44757  0.40745  0.45117  0.40594  2856  # incandescent / tungsten
  B        0.34842  0.35161  0.34980  0.35270  4874  # obsolete, direct sunlight at noon
  C        0.31006  0.31616  0.31039  0.31905  6774  # obsolete, average / North sky daylight
  D50      0.34567  0.35850  0.34773  0.35952  5003  # horizon light, ICC profile PCS
  D55      0.33242  0.34743  0.33411  0.34877  5503  # mid-morning / mid-afternoon daylight
  D65      0.31271  0.32902  0.31382  0.33100  6504  # noon daylight: television, sRGB color space
  D75      0.29902  0.31485  0.29968  0.31740  7504  # North sky daylight
  D93      0.28315  0.29711  0.28327  0.30043  9305  # high-efficiency blue phosphor monitors, BT.2035
  E        0.33333  0.33333  0.33333  0.33333  5454  # equal energy
  F1       0.31310  0.33727  0.31811  0.33559  6430  # daylight fluorescent
  F2       0.37208  0.37529  0.37925  0.36733  4230  # cool white fluorescent
  F3       0.40910  0.39430  0.41761  0.38324  3450  # white fluorescent
  F4       0.44018  0.40329  0.44920  0.39074  2940  # warm white fluorescent
  F5       0.31379  0.34531  0.31975  0.34246  6350  # daylight fluorescent
  F6       0.37790  0.38835  0.38660  0.37847  4150  # light white fluorescent
  F7       0.31292  0.32933  0.31569  0.32960  6500  # D65 simulator, daylight simulator
  F8       0.34588  0.35875  0.34902  0.35939  5000  # D50 simulator, Sylvania F40 Design 50
  F9       0.37417  0.37281  0.37829  0.37045  4150  # cool white deluxe fluorescent
  F10      0.34609  0.35986  0.35090  0.35444  5000  # Philips TL85, Ultralume 50
  F11      0.38052  0.37713  0.38541  0.37123  4000  # Philips TL84, Ultralume 40
  F12      0.43695  0.40441  0.44256  0.39717  3000  # Philips TL83, Ultralume 30
  LED-B1   0.4560   0.4078   _        _        2733  # phosphor-converted blue
  LED-B2   0.4357   0.4012   _        _        2998  # phosphor-converted blue
  LED-B3   0.3756   0.3723   _        _        4103  # phosphor-converted blue
  LED-B4   0.3422   0.3502   _        _        5109  # phosphor-converted blue
  LED-B5   0.3118   0.3236   _        _        6598  # phosphor-converted blue
  LED-BH1  0.4474   0.4066   _        _        2851  # mixing of phosphor-converted blue LED and red LED (blue-hybrid)
  LED-RGB1 0.4557   0.4211   _        _        2840  # mixing of red, green, and blue LEDs
  LED-V1   0.4560   0.4548   _        _        2724  # phosphor-converted violet
  LED-V2   0.3781   0.3775   _        _        4070  # phosphor-converted violet

  # For the following illuminants, the 10° chomaticity comes from the Python `colour_science` library

  # CIE 184:2009 Indoor Daylight Illuminants
  # https://www.researchgate.net/publication/328812649_CIE_1842009_Indoor_Daylight_Illuminants
  ID65     0.3106   0.3306   0.31207  0.33266  6504  # indoor daylight d65
  ID50     0.3432   0.3602   0.34562  0.36122  5003  # indoor daylight d50

  # From TB-2018-001 Derivation of the ACES white point CIE chromaticity coordinates
  D60      0.32168  0.33767  0.32298  0.33927  5998  # Academy of Motion Picture Arts and Sciences

  # DCI P3 https://en.wikipedia.org/wiki/DCI-P3
  P3_DCI   0.314    0.351    _        _        6300  # Non-CIE Illuminant

  """

  @illuminant_aliases %{
    P3_D65: :D65,
    Rec709: :D65,
    Rec2020: :D65,
    Cinema_Gamut: :D65,
    P3_DCI_P: :P3_DCI,
    ACES: :D60
  }

  @illuminants @xyz_tristimulus_table
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn line ->
      line
      |> String.split("\s", trim: true)
      |> hd
      |> String.to_atom()
    end)

  def illuminants do
    @illuminants
  end

  @xyz_tristimulus @xyz_tristimulus_table
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.flat_map(fn line ->
      [illuminant | data] =
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

      [cie1931, cie1964, _cct] = Enum.chunk_every(data, 2)
      cie1931 = Color.XYY.to_xyz_tensor(cie1931)
      cie1964 = Color.XYY.to_xyz_tensor(cie1964)

      case Enum.reject([cie1931, cie1964], &is_nil/1) do
        [cie1931] ->
          [{{String.to_atom(illuminant), 2}, cie1931}]

        [cie1931, cie1964] ->
          [
            {{String.to_atom(illuminant), 2}, cie1931},
            {{String.to_atom(illuminant), 10}, cie1964}
          ]
      end
    end)
    |> Map.new()

  defn tristimulus do
    @xyz_tristimulus
  end

  def tristimulus(illuminant, observer_angle) do
    with {:ok, illuminant} <- validate_illuminant(illuminant),
         {:ok, observer_angle} <- validate_observer_angle(observer_angle) do
      case Map.fetch(tristimulus(), {illuminant, observer_angle}) do
        {:ok, tristimulus} ->
          {:ok, tristimulus}

        _other ->
          {:error,
           "Illuminant #{inspect(illuminant)} has no tristimulus " <>
             "for #{inspect(observer_angle)}° observer angle."}
      end
    end
  end

  defp validate_illuminant(illuminant) when illuminant in @illuminants do
    {:ok, illuminant}
  end

  defp validate_illuminant(illuminant) do
    {:error,
     "Invalid illuminant #{inspect(illuminant)}.  " <>
       "Valid illuminants are #{inspect(@illuminants)}"}
  end

  defp validate_observer_angle(observer_angle) when observer_angle in @observer_angles do
    {:ok, observer_angle}
  end

  defp validate_observer_angle(observer_angle) do
    {:error,
     "Unknown observer angle #{inspect(observer_angle)}. " <>
       "Valid observer angles are #{inspect(@observer_angles)}"}
  end
end
