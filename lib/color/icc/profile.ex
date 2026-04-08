defmodule Color.ICC.Profile do
  @moduledoc """
  Reader for ICC v2 / v4 **matrix profiles** — the form used by
  `sRGB IEC61966-2.1.icc`, `Display P3.icc`, `AdobeRGB1998.icc`,
  `Generic Lab Profile.icc`, and most camera and scanner profiles.

  This is intentionally a small subset of the ICC specification:

  * Only **input** profiles with the **RGB** colour space and the
    **XYZ** profile connection space are supported.

  * Only the matrix-TRC tag set is read: `rXYZ`, `gXYZ`, `bXYZ`,
    `rTRC`, `gTRC`, `bTRC`, plus `wtpt` and `desc`.

  * `curv` (LUT) and `para` (parametric, types 0–4) tone response
    curves are both supported.

  * LUT-based profiles (`mft1`, `mft2`, `mAB ` / `mBA `) are not
    supported. Pass them through `lcms2` via a NIF if you need them.

  ## Workflow

      {:ok, profile} = Color.ICC.Profile.load("/path/to/sRGB Profile.icc")
      profile.description           # "sRGB IEC61966-2.1"
      profile.white_point           # {0.9642, 1.0, 0.8249}  (PCS, D50)
      profile.matrix                # 3x3 column-XYZ list
      profile.trc.r                 # %{type: :curve, gamma: 2.4} or {:lut, list}

  Once loaded, a profile can be applied to encoded RGB values:

      Color.ICC.Profile.to_xyz(profile, {0.5, 0.5, 0.5})
      # => {x, y, z} in the PCS (D50)

      Color.ICC.Profile.from_xyz(profile, {0.9642, 1.0, 0.8249})
      # => {1.0, 1.0, 1.0}

  The PCS for matrix profiles is always D50 / 2° observer; this
  module emits raw XYZ in that frame and leaves any chromatic
  adaptation to the caller (`Color.XYZ.adapt/3`).

  """

  defstruct [
    :version,
    :class,
    :colour_space,
    :pcs,
    :description,
    :white_point,
    :matrix,
    :trc
  ]

  @type t :: %__MODULE__{
          version: String.t(),
          class: atom(),
          colour_space: atom(),
          pcs: atom(),
          description: String.t(),
          white_point: {float(), float(), float()},
          matrix: [list()],
          trc: %{r: trc(), g: trc(), b: trc()}
        }

  @typedoc "A tone response curve."
  @type trc ::
          {:gamma, float()}
          | {:lut, [float()]}
          | {:parametric, atom(), [float()]}

  @doc """
  Loads an ICC matrix profile from the filesystem.

  ### Arguments

  * `path` is a binary file path.

  ### Returns

  * `{:ok, %Color.ICC.Profile{}}` on success.

  * `{:error, exception}` if the file cannot be read or is not a
    matrix profile.

  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, Exception.t()}
  def load(path) when is_binary(path) do
    case File.read(path) do
      {:ok, binary} -> parse(binary)
      {:error, posix} -> {:error, %File.Error{reason: posix, action: "read", path: path}}
    end
  end

  @doc """
  Parses an ICC profile from a binary already in memory.

  ### Arguments

  * `binary` is the full profile bytes.

  ### Returns

  * `{:ok, %Color.ICC.Profile{}}` or `{:error, exception}`.

  """
  @spec parse(binary()) :: {:ok, t()} | {:error, Exception.t()}
  def parse(binary) when is_binary(binary) and byte_size(binary) >= 128 do
    with {:ok, header} <- parse_header(binary),
         {:ok, tags} <- parse_tag_table(binary),
         :ok <- check_supported(header) do
      build_profile(binary, header, tags)
    end
  end

  def parse(_) do
    {:error, %Color.ICC.ParseError{reason: :too_short}}
  end

  @doc """
  Converts an encoded RGB triple in the profile's colour space to
  PCS XYZ (D50).

  ### Arguments

  * `profile` is a `Color.ICC.Profile` struct.

  * `rgb` is an `{r, g, b}` tuple of unit floats `[0, 1]`.

  ### Returns

  * An `{x, y, z}` tuple of floats in the PCS (D50, 2° observer).

  """
  @spec to_xyz(t(), {number(), number(), number()}) :: {float(), float(), float()}
  def to_xyz(%__MODULE__{trc: trc, matrix: m}, {r, g, b}) do
    rl = apply_trc(trc.r, r)
    gl = apply_trc(trc.g, g)
    bl = apply_trc(trc.b, b)

    [[m11, m12, m13], [m21, m22, m23], [m31, m32, m33]] = m

    {
      m11 * rl + m12 * gl + m13 * bl,
      m21 * rl + m22 * gl + m23 * bl,
      m31 * rl + m32 * gl + m33 * bl
    }
  end

  @doc """
  Converts a PCS (D50) XYZ triple back to encoded RGB in the
  profile's colour space.

  ### Arguments

  * `profile` is a `Color.ICC.Profile` struct.

  * `xyz` is an `{x, y, z}` tuple in the PCS (D50, 2° observer).

  ### Returns

  * An `{r, g, b}` tuple of unit floats. May be outside `[0, 1]`
    for out-of-gamut inputs; clip or gamut-map separately.

  """
  @spec from_xyz(t(), {number(), number(), number()}) :: {float(), float(), float()}
  def from_xyz(%__MODULE__{trc: trc, matrix: m}, {x, y, z}) do
    inv = Color.Conversion.Lindbloom.invert3(m)
    [[i11, i12, i13], [i21, i22, i23], [i31, i32, i33]] = inv

    rl = i11 * x + i12 * y + i13 * z
    gl = i21 * x + i22 * y + i23 * z
    bl = i31 * x + i32 * y + i33 * z

    {
      apply_inverse_trc(trc.r, rl),
      apply_inverse_trc(trc.g, gl),
      apply_inverse_trc(trc.b, bl)
    }
  end

  # ----- header ---------------------------------------------------------

  defp parse_header(<<
         _profile_size::32,
         _cmm::4-bytes,
         major::8,
         minor::8,
         _bug_fix::16,
         class::4-bytes,
         colour_space::4-bytes,
         pcs::4-bytes,
         _date::12-bytes,
         "acsp",
         _rest::binary
       >>) do
    {:ok,
     %{
       version: "#{major}.#{minor}",
       class: profile_class(class),
       colour_space: colour_space_atom(colour_space),
       pcs: colour_space_atom(pcs)
     }}
  end

  defp parse_header(_), do: {:error, %Color.ICC.ParseError{reason: :bad_header}}

  defp profile_class("scnr"), do: :input
  defp profile_class("mntr"), do: :display
  defp profile_class("prtr"), do: :output
  defp profile_class("link"), do: :device_link
  defp profile_class("spac"), do: :colour_space
  defp profile_class("abst"), do: :abstract
  defp profile_class("nmcl"), do: :named_colour
  defp profile_class(other), do: {:unknown, other}

  defp colour_space_atom("RGB "), do: :rgb
  defp colour_space_atom("CMYK"), do: :cmyk
  defp colour_space_atom("GRAY"), do: :grey
  defp colour_space_atom("XYZ "), do: :xyz
  defp colour_space_atom("Lab "), do: :lab
  defp colour_space_atom("YCbr"), do: :ycbcr
  defp colour_space_atom(other), do: {:unknown, other}

  defp check_supported(%{class: _class, colour_space: :rgb, pcs: :xyz}), do: :ok

  defp check_supported(header) do
    {:error,
     %Color.ICC.ParseError{
       reason: :unsupported_profile,
       details: header
     }}
  end

  # ----- tag table ------------------------------------------------------

  defp parse_tag_table(<<_::128-bytes, count::32, rest::binary>>) when count > 0 do
    parse_tags(rest, count, %{})
  end

  defp parse_tag_table(_), do: {:error, %Color.ICC.ParseError{reason: :no_tag_table}}

  defp parse_tags(_rest, 0, acc), do: {:ok, acc}

  defp parse_tags(<<sig::4-bytes, offset::32, size::32, rest::binary>>, count, acc) do
    parse_tags(rest, count - 1, Map.put(acc, sig, {offset, size}))
  end

  defp parse_tags(_, _, _), do: {:error, %Color.ICC.ParseError{reason: :truncated_tag_table}}

  # ----- profile assembly -----------------------------------------------

  @required_tags ["rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC"]

  defp build_profile(binary, header, tags) do
    case Enum.find(@required_tags, fn t -> not Map.has_key?(tags, t) end) do
      nil ->
        with {:ok, r_xyz} <- read_xyz(binary, tags["rXYZ"]),
             {:ok, g_xyz} <- read_xyz(binary, tags["gXYZ"]),
             {:ok, b_xyz} <- read_xyz(binary, tags["bXYZ"]),
             {:ok, r_trc} <- read_trc(binary, tags["rTRC"]),
             {:ok, g_trc} <- read_trc(binary, tags["gTRC"]),
             {:ok, b_trc} <- read_trc(binary, tags["bTRC"]) do
          white_point =
            case Map.fetch(tags, "wtpt") do
              {:ok, loc} -> elem(read_xyz(binary, loc), 1)
              :error -> {0.9642, 1.0, 0.8249}
            end

          description =
            case Map.fetch(tags, "desc") do
              {:ok, loc} -> elem(read_desc(binary, loc), 1)
              :error -> ""
            end

          matrix = [
            [elem(r_xyz, 0), elem(g_xyz, 0), elem(b_xyz, 0)],
            [elem(r_xyz, 1), elem(g_xyz, 1), elem(b_xyz, 1)],
            [elem(r_xyz, 2), elem(g_xyz, 2), elem(b_xyz, 2)]
          ]

          {:ok,
           %__MODULE__{
             version: header.version,
             class: header.class,
             colour_space: header.colour_space,
             pcs: header.pcs,
             description: description,
             white_point: white_point,
             matrix: matrix,
             trc: %{r: r_trc, g: g_trc, b: b_trc}
           }}
        end

      missing ->
        {:error,
         %Color.ICC.ParseError{
           reason: :missing_tag,
           details: missing
         }}
    end
  end

  # ----- tag readers ----------------------------------------------------

  defp read_xyz(binary, {offset, size}) when size >= 20 do
    tag = :binary.part(binary, offset, size)

    case tag do
      <<"XYZ ", 0::32, x::32-signed, y::32-signed, z::32-signed, _rest::binary>> ->
        {:ok, {s15_fixed_16(x), s15_fixed_16(y), s15_fixed_16(z)}}

      _ ->
        {:error, %Color.ICC.ParseError{reason: :bad_xyz_tag}}
    end
  end

  defp read_xyz(_, _), do: {:error, %Color.ICC.ParseError{reason: :bad_xyz_tag}}

  defp read_trc(binary, {offset, size}) do
    tag = :binary.part(binary, offset, size)

    case tag do
      <<"curv", 0::32, count::32, rest::binary>> ->
        case count do
          0 ->
            {:ok, {:gamma, 1.0}}

          1 ->
            <<gamma_u8::16, _::binary>> = rest
            # u8Fixed8Number
            {:ok, {:gamma, gamma_u8 / 256.0}}

          n ->
            entries = for <<v::16 <- :binary.part(rest, 0, n * 2)>>, do: v / 65535.0
            {:ok, {:lut, entries}}
        end

      <<"para", 0::32, type::16, _reserved::16, rest::binary>> ->
        params = read_para_params(type, rest)
        {:ok, {:parametric, parametric_type(type), params}}

      _ ->
        {:error, %Color.ICC.ParseError{reason: :bad_trc_tag}}
    end
  end

  defp read_para_params(type, rest) do
    n =
      case type do
        0 -> 1
        1 -> 3
        2 -> 4
        3 -> 5
        4 -> 7
        _ -> 0
      end

    for <<v::32-signed <- :binary.part(rest, 0, n * 4)>>, do: s15_fixed_16(v)
  end

  defp parametric_type(0), do: :gamma
  defp parametric_type(1), do: :cie122_1996
  defp parametric_type(2), do: :iec61966_3
  defp parametric_type(3), do: :iec61966_2_1
  defp parametric_type(4), do: :extended

  defp read_desc(binary, {offset, size}) do
    tag = :binary.part(binary, offset, size)

    case tag do
      <<"mluc", 0::32, _records::32, _rec_size::32, rest::binary>> ->
        # First record: lang(2) country(2) length(4) offset(4 — relative to start of tag)
        <<_lang::16, _country::16, length::32, str_offset::32, _::binary>> = rest

        text =
          tag
          |> :binary.part(str_offset, length)
          |> :unicode.characters_to_binary({:utf16, :big})

        {:ok, text}

      <<"desc", 0::32, length::32, rest::binary>> ->
        # ASCII description
        text = :binary.part(rest, 0, max(length - 1, 0))
        {:ok, text}

      _ ->
        {:ok, ""}
    end
  end

  # ----- TRC application ------------------------------------------------

  defp apply_trc({:gamma, gamma}, v) when v >= 0, do: :math.pow(v, gamma)
  defp apply_trc({:gamma, _gamma}, _v), do: 0.0

  defp apply_trc({:lut, [single]}, v), do: apply_trc({:gamma, single}, v)

  defp apply_trc({:lut, entries}, v) do
    interpolate_lut(entries, v)
  end

  defp apply_trc({:parametric, :gamma, [g]}, v) when v >= 0, do: :math.pow(v, g)
  defp apply_trc({:parametric, :gamma, _}, _), do: 0.0

  defp apply_trc({:parametric, :iec61966_2_1, [g, a, b, c, d]}, v) do
    if v >= d do
      :math.pow(a * v + b, g)
    else
      c * v
    end
  end

  defp apply_trc({:parametric, _other, _params}, v), do: v

  defp apply_inverse_trc({:gamma, gamma}, v) when v >= 0, do: :math.pow(v, 1 / gamma)
  defp apply_inverse_trc({:gamma, _gamma}, _v), do: 0.0

  defp apply_inverse_trc({:lut, [single]}, v),
    do: apply_inverse_trc({:gamma, single}, v)

  defp apply_inverse_trc({:lut, entries}, v) do
    inverse_interpolate_lut(entries, v)
  end

  defp apply_inverse_trc({:parametric, :gamma, [g]}, v) when v >= 0,
    do: :math.pow(v, 1 / g)

  defp apply_inverse_trc({:parametric, :gamma, _}, _), do: 0.0

  defp apply_inverse_trc({:parametric, :iec61966_2_1, [g, a, b, c, d]}, v) do
    threshold = c * d

    if v >= threshold do
      (:math.pow(v, 1 / g) - b) / a
    else
      v / c
    end
  end

  defp apply_inverse_trc({:parametric, _other, _params}, v), do: v

  defp interpolate_lut(entries, v) when v <= 0.0, do: hd(entries)

  defp interpolate_lut(entries, v) when v >= 1.0, do: List.last(entries)

  defp interpolate_lut(entries, v) do
    n = length(entries) - 1
    pos = v * n
    lo = trunc(pos)
    hi = min(lo + 1, n)
    t = pos - lo

    a = Enum.at(entries, lo)
    b = Enum.at(entries, hi)
    a + (b - a) * t
  end

  defp inverse_interpolate_lut(entries, v) do
    # Linear search for the bracketing pair, then linear interp.
    indexed = Enum.with_index(entries)

    case Enum.find(indexed, fn {e, _i} -> e >= v end) do
      nil ->
        1.0

      {e, 0} when e >= v ->
        0.0

      {e, i} ->
        prev = Enum.at(entries, i - 1)

        if e == prev,
          do: (i - 1) / (length(entries) - 1),
          else: (i - 1 + (v - prev) / (e - prev)) / (length(entries) - 1)
    end
  end

  # s15Fixed16Number → float
  defp s15_fixed_16(int), do: int / 65536.0
end
