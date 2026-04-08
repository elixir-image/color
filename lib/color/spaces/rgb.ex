defmodule Color.RGB do
  @moduledoc """
  Linear (un-companded) RGB relative to a named working space.

  See `Color.SRGB` for the companded sRGB working-space color type.
  This module covers every RGB working space listed in
  `Color.RGB.WorkingSpace`: `:SRGB`, `:Adobe`, `:ProPhoto`, `:Rec709`,
  `:Rec2020` etc. Channels are unit floats.

  The working-space conversion matrix is computed lazily and memoised
  in `:persistent_term`, so the first call for a given working space
  pays the Lindbloom derivation cost once and subsequent calls are a
  plain `:persistent_term.get/1`.

  """

  alias Color.Conversion.Lindbloom

  defstruct [:r, :g, :b, :alpha, :working_space]

  @typedoc """
  Linear RGB in any named working space. The `working_space` field
  identifies which set of primaries and reference white to use; see
  `Color.RGB.WorkingSpace.rgb_working_spaces/0` for the full list.
  """
  @type t :: %__MODULE__{
          r: float() | nil,
          g: float() | nil,
          b: float() | nil,
          alpha: Color.Types.alpha(),
          working_space: Color.Types.working_space() | nil
        }

  @doc """
  Converts a linear RGB color to CIE `XYZ`.

  ### Arguments

  * `rgb` is a `Color.RGB` struct whose `:working_space` names an RGB
    working space (for example `:SRGB`, `:Adobe`, `:ProPhoto`).

  ### Returns

  * A `Color.XYZ` struct tagged with the working space's illuminant
    and 2° observer angle.

  ### Examples

      iex> {:ok, xyz} = Color.RGB.to_xyz(%Color.RGB{r: 1.0, g: 1.0, b: 1.0, working_space: :SRGB})
      iex> {Float.round(xyz.x, 4), Float.round(xyz.y, 4)}
      {0.9505, 1.0}

  """
  def to_xyz(%__MODULE__{r: r, g: g, b: b, alpha: alpha, working_space: space}) do
    info = working_space_info(space)
    {x, y, z} = Lindbloom.rgb_to_xyz({r, g, b}, info.to_xyz)

    {:ok,
     %Color.XYZ{
       x: x,
       y: y,
       z: z,
       alpha: alpha,
       illuminant: info.illuminant,
       observer_angle: info.observer_angle
     }}
  end

  @doc """
  Converts a CIE `XYZ` color to linear RGB in the given working space.

  ### Arguments

  * `xyz` is a `Color.XYZ` struct. Its illuminant must match the working
    space — if not, chromatically adapt first.

  * `working_space` is an atom naming the target RGB working space.

  ### Returns

  * A `Color.RGB` struct.

  ### Examples

      iex> xyz = %Color.XYZ{x: 0.95047, y: 1.0, z: 1.08883, illuminant: :D65, observer_angle: 2}
      iex> {:ok, rgb} = Color.RGB.from_xyz(xyz, :SRGB)
      iex> {Float.round(rgb.r, 3), Float.round(rgb.g, 3), Float.round(rgb.b, 3)}
      {1.0, 1.0, 1.0}

  """
  def from_xyz(%Color.XYZ{x: x, y: y, z: z, alpha: alpha}, working_space) do
    info = working_space_info(working_space)
    {r, g, b} = Lindbloom.xyz_to_rgb({x, y, z}, info.from_xyz)

    {:ok, %__MODULE__{r: r, g: g, b: b, alpha: alpha, working_space: working_space}}
  end

  defp working_space_info(space) do
    key = {__MODULE__, :matrix, space}

    case :persistent_term.get(key, :__uncached__) do
      :__uncached__ ->
        {:ok, info} = Color.RGB.WorkingSpace.rgb_conversion_matrix(space)
        :persistent_term.put(key, info)
        info

      info ->
        info
    end
  end
end
