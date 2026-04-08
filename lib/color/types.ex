defmodule Color.Types do
  @moduledoc """
  Shared type aliases used across the `Color` library.

  Pulled out into a separate module so the per-space struct modules
  and the top-level `Color` module can refer to a single canonical
  definition for things like alpha, illuminant, observer angle, and
  rendering intent.

  ## Examples

      @spec lighten(Color.SRGB.t(), Color.Types.alpha()) :: Color.SRGB.t()
  """

  @typedoc """
  An alpha (opacity) value, always a unit float in `[0.0, 1.0]`, or
  `nil` to mean "not set / fully opaque". Alpha is straight
  (unassociated) throughout the library.
  """
  @type alpha :: float() | nil

  @typedoc """
  A reference white. The standard CIE illuminants supported by the
  library.

  * `:D50` — ICC PCS, used by CSS Color 4 `lab()` and `lch()`.
  * `:D65` — sRGB, Display P3, Rec. 709, Rec. 2020. The default for
    most modern computing colour science.
  * `:D55`, `:D75` — alternative daylight illuminants.
  * `:A` — incandescent / tungsten ~2856 K.
  * `:B` — direct sunlight at noon (deprecated by CIE but still in
    legacy data).
  * `:C` — average / north-sky daylight (NTSC 1953).
  * `:E` — equi-energy radiator (theoretical, all wavelengths equal).
  * `:F2`, `:F7`, `:F11` — fluorescent series (cool white, broadband
    daylight, narrow-band).
  """
  @type illuminant :: :A | :B | :C | :D50 | :D55 | :D65 | :D75 | :E | :F2 | :F7 | :F11

  @typedoc """
  CIE standard observer angle, in degrees. `2` is the 1931
  ("standard") observer; `10` is the 1964 ("supplementary") observer.
  """
  @type observer :: 2 | 10

  @typedoc """
  An ICC rendering intent.

  * `:relative_colorimetric` (default) — chromatically adapt the
    source white to the target white. Out-of-gamut colors are
    *not* altered.
  * `:absolute_colorimetric` — no chromatic adaptation. The source
    XYZ is handed to the target's `from_xyz/1` verbatim.
  * `:perceptual` — chromatically adapt **and** gamut-map so the
    result is inside the target's gamut.
  * `:saturation` — alias for `:perceptual` in the current
    implementation. A future release may add a true saturation
    intent.
  """
  @type intent :: :relative_colorimetric | :absolute_colorimetric | :perceptual | :saturation

  @typedoc """
  A chromatic adaptation method, used to convert between reference
  whites. Bradford is the default and is what ICC v4 specifies for
  D50↔D65.
  """
  @type adaptation_method ::
          :bradford | :cat02 | :von_kries | :sharp | :cmccat2000 | :xyz_scaling

  @typedoc """
  Short atom identifiers for colour spaces. Accepted by `Color.new/2`
  and the option list of `Color.convert/3`.
  """
  @type space ::
          :srgb
          | :sRGB
          | :adobe_rgb
          | :adobe
          | :rgb
          | :cmyk
          | :hsl
          | :hsv
          | :hsluv
          | :hpluv
          | :lab
          | :lch
          | :lchab
          | :luv
          | :lchuv
          | :oklab
          | :oklch
          | :xyz
          | :xyy
          | :xyY
          | :jzazbz
          | :ictcp
          | :ipt
          | :ycbcr
          | :cam16
          | :cam16_ucs

  @typedoc """
  An RGB working space identifier (the value passed as the third
  argument to `Color.convert/3` when the target is `Color.RGB`).
  See `Color.RGB.WorkingSpace.rgb_working_spaces/0` for the full
  list.
  """
  @type working_space ::
          :SRGB
          | :Adobe
          | :Apple
          | :Best
          | :Beta
          | :Bruce
          | :CIE
          | :ColorMatch
          | :Don4
          | :ECI
          | :EktaSpace
          | :NTSC
          | :PAL_SECAM
          | :ProPhoto
          | :SMPTE_C
          | :WideGamut
          | :P3_D65
          | :P3_D60
          | :Rec2020
          | :Rec709
          | :ACES
          | :ACEScg
          | :ACES_AP1
          | :Adobe_Wide
end
