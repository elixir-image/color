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

  # Calculate the tristimulus values for a range of
  # illuminants and the two standard observer angles
  # Numbers taken from https://www.easyrgb.com/en/math.php
  # with correctins applied for CIE1931 from
  # http://www.brucelindbloom.com/index.html?Calc.html

  @xyz_tristimulus_table """
  # Observer       2° (CIE 1931)            10° (CIE 1964)        Note
  # Illuminant  X2      Y2      Z2       X10      Y10     Z10
  A          109.850  100.000  35.585  111.144  100.000  35.200   # Incandescent/tungsten
  B          99.0972  100.000  85.223  99.178   100.000  84.3493  # Old direct sunlight at noon
  C          98.074   100.000  118.232 97.285   100.000  116.145  # Old daylight
  D50        96.422   100.000  82.521  96.720   100.000  81.427   # ICC profile PCS
  D55        95.682   100.000  92.149  95.799   100.000  90.926   # Mid-morning daylight
  D65        95.047   100.000  108.883 94.811   100.000  107.304  # Daylight, sRGB, Adobe-RGB
  D75        94.972   100.000  122.638 94.416   100.000  120.641  # North sky daylight
  E          100.000  100.000  100.000 100.000  100.000  100.000  # Equal energy
  F1         92.834   100.000  103.665 94.791   100.000  103.191  # Daylight Fluorescent
  F2         99.186   100.000  67.393  103.280  100.000  69.026   # Cool fluorescent
  F3         103.754  100.000  49.861  108.968  100.000  51.965   # White Fluorescent
  F4         109.147  100.000  38.813  114.961  100.000  40.963   # Warm White Fluorescent
  F5         90.872   100.000  98.723  93.369   100.000  98.636   # Daylight Fluorescent
  F6         97.309   100.000  60.191  102.148  100.000  62.074   # Lite White Fluorescent
  F7         95.041   100.000  108.747 95.792   100.000  107.687  # Daylight fluorescent, D65 simulator
  F8         96.413   100.000  82.333  97.115   100.000  81.135   # Sylvania F40, D50 simulator
  F9         100.365  100.000  67.868  102.116  100.000  67.826   # Cool White Fluorescent
  F10        96.174   100.000  81.712  99.001   100.000  83.134   # Ultralume 50, Philips TL85
  F11        100.962  100.000  64.350  103.866  100.000  65.627   # Ultralume 40, Philips TL84
  F12        108.046  100.000  39.228  111.428  100.000  40.353   # Ultralume 30, Philips TL83
  """

  @xyz_illuminants @xyz_tristimulus_table
  |> String.split("\n", trim: true)
  |> Enum.reject(&String.starts_with?(&1, "#"))
  |> Enum.map(fn line ->
    line
    |> String.split("\s", trim: true)
    |> hd
    |> String.to_atom()
  end)

  def illuminants do
    @xyz_illuminants
  end

  @xyz_tristimulus @xyz_tristimulus_table
  |> String.split("\n", trim: true)
  |> Enum.reject(&String.starts_with?(&1, "#"))
  |> Enum.map(fn line ->
    [illuminant | data] =
      line
      |> String.split("#")
      |> hd()
      |> String.split("\s", trim: true)
      |> Enum.map(fn elem ->
        case Float.parse(elem) do
          {float, ""} -> float / 100
          :error -> elem
        end
      end)

    [cie1931, cie1964] = Enum.chunk_every(data, 3)
    {String.to_atom(illuminant), {Nx.tensor(cie1931), Nx.tensor(cie1964)}}
  end)
  |> Map.new()

  defn tristimulus do
    @xyz_tristimulus
  end

  def tristimulus(illuminant, observer_angle) do
    with {:ok, illuminant} <- validate_illuminant(illuminant),
         {:ok, observer_angle} <- validate_observer_angle(observer_angle) do
      case observer_angle do
        2 ->
          {:ok, Map.fetch!(tristimulus(), illuminant) |> elem(0)}
        10 ->
          {:ok, Map.fetch!(tristimulus(), illuminant) |> elem(1)}
      end
   end
  end

  def validate_illuminant(illuminant) do
    if illuminant in illuminants() do
      {:ok, illuminant}
    else
      {:error, "Invalid illuminant #{inspect illuminant}.  Valid illuminants are #{inspect @xyz_illuminants}"}
    end
  end

  def validate_observer_angle(observer_angle) do
    if observer_angle in @observer_angles do
      {:ok, observer_angle}
    else
      {:error, "Unknown observer angle. Valid observer angles are #{inspect @observer_angles}"}
    end
  end
end