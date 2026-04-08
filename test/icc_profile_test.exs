defmodule Color.ICC.ProfileTest do
  @moduledoc """
  Tests for the ICC matrix-profile reader. Since we don't ship any
  ICC files in the repo, the tests build a tiny synthetic profile in
  memory and run the parser over it. The synthetic profile is
  modelled on the sRGB IEC61966-2.1 profile: gamma 2.2 TRCs, sRGB
  primary XYZ values in the PCS (D50).
  """
  use ExUnit.Case, async: true

  alias Color.ICC.Profile

  # ----------------------------------------------------------------------
  # Synthetic profile builder
  # ----------------------------------------------------------------------

  defp s15(value) when is_number(value), do: round(value * 65536)

  defp xyz_tag(x, y, z) do
    <<"XYZ ", 0::32, s15(x)::32-signed, s15(y)::32-signed, s15(z)::32-signed>>
  end

  defp curv_gamma_tag(gamma) do
    # u8Fixed8Number with one entry
    g = round(gamma * 256)
    <<"curv", 0::32, 1::32, g::16>>
  end

  defp pad4(binary) do
    case rem(byte_size(binary), 4) do
      0 -> binary
      n -> binary <> :binary.copy(<<0>>, 4 - n)
    end
  end

  defp build_synthetic_profile do
    # The minimal profile we build:
    #   header (128 bytes)
    #   tag table (4 + 12*6)
    #   six tag bodies (rXYZ, gXYZ, bXYZ, rTRC, gTRC, bTRC)

    # sRGB primaries in PCS (D50). Values from the sRGB IEC61966-2.1
    # ICC profile (rounded). The rXYZ, gXYZ, bXYZ tag values are the
    # *columns* of the linear sRGB → PCS XYZ matrix, which is the
    # Bradford-adapted sRGB → D50 matrix.
    r_xyz_body = xyz_tag(0.4360, 0.2225, 0.0139)
    g_xyz_body = xyz_tag(0.3851, 0.7169, 0.0971)
    b_xyz_body = xyz_tag(0.1431, 0.0606, 0.7139)

    # Use simple gamma 2.2 TRCs for testability. (Real sRGB uses a
    # parametric curve; we test that path separately below.)
    trc_body = curv_gamma_tag(2.2)

    bodies = [
      {"rXYZ", r_xyz_body},
      {"gXYZ", g_xyz_body},
      {"bXYZ", b_xyz_body},
      {"rTRC", trc_body},
      {"gTRC", trc_body},
      {"bTRC", trc_body}
    ]

    header_size = 128
    tag_count_size = 4
    tag_entry_size = 12
    tag_table_size = tag_count_size + tag_entry_size * length(bodies)

    {tags, _, body_blob} =
      Enum.reduce(bodies, {[], header_size + tag_table_size, <<>>}, fn
        {sig, body}, {acc, offset, blob} ->
          padded = pad4(body)
          entry = {sig, offset, byte_size(body)}
          {[entry | acc], offset + byte_size(padded), blob <> padded}
      end)

    tags = Enum.reverse(tags)

    tag_table =
      <<length(tags)::32>> <>
        Enum.reduce(tags, <<>>, fn {sig, offset, size}, acc ->
          acc <> <<sig::binary, offset::32, size::32>>
        end)

    profile_size = header_size + tag_table_size + byte_size(body_blob)

    header = build_header(profile_size)

    header <> tag_table <> body_blob
  end

  defp build_header(profile_size) do
    # Header: profile_size(4), CMM(4), version(4), class(4),
    # colour_space(4), pcs(4), date(12), magic(4), platform(4),
    # flags(4), manufacturer(4), model(4), attributes(8),
    # rendering_intent(4), illuminant(12), creator(4), id(16),
    # reserved(28). Total: 128 bytes.

    <<profile_size::32, "lcms", 4::8, 0::8, 0::16, "scnr", "RGB ", "XYZ ", 0::96, "acsp", "APPL",
      0::32, "ELXR", 0::32, 0::64, 0::32, 0::96, 0::32, 0::128, 0::224>>
  end

  # ----------------------------------------------------------------------
  # Tests
  # ----------------------------------------------------------------------

  test "parses a synthetic minimal matrix profile" do
    profile_binary = build_synthetic_profile()
    {:ok, profile} = Profile.parse(profile_binary)

    assert profile.class == :input
    assert profile.colour_space == :rgb
    assert profile.pcs == :xyz
    assert profile.version == "4.0"

    # Matrix should be the column-XYZ values we wrote.
    [[m11, m12, m13], [m21, m22, m23], [m31, m32, m33]] = profile.matrix
    assert_in_delta m11, 0.4360, 1.0e-4
    assert_in_delta m12, 0.3851, 1.0e-4
    assert_in_delta m13, 0.1431, 1.0e-4
    assert_in_delta m21, 0.2225, 1.0e-4
    assert_in_delta m22, 0.7169, 1.0e-4
    assert_in_delta m23, 0.0606, 1.0e-4
    assert_in_delta m31, 0.0139, 1.0e-4
    assert_in_delta m32, 0.0971, 1.0e-4
    assert_in_delta m33, 0.7139, 1.0e-4

    assert {:gamma, gamma} = profile.trc.r
    assert_in_delta gamma, 2.2, 0.01
  end

  test "to_xyz / from_xyz round-trip with the synthetic profile" do
    profile_binary = build_synthetic_profile()
    {:ok, profile} = Profile.parse(profile_binary)

    inputs = [
      {0.5, 0.25, 0.75},
      {1.0, 1.0, 1.0},
      {0.0, 0.0, 0.0},
      {0.7, 0.5, 0.3}
    ]

    for {r, g, b} <- inputs do
      xyz = Profile.to_xyz(profile, {r, g, b})
      {ro, go, bo} = Profile.from_xyz(profile, xyz)

      assert_in_delta ro, r, 1.0e-3
      assert_in_delta go, g, 1.0e-3
      assert_in_delta bo, b, 1.0e-3
    end
  end

  test "rejects a binary that is too short" do
    assert {:error, %Color.ICC.ParseError{reason: :too_short}} =
             Profile.parse(<<0::32>>)
  end

  test "rejects a binary that is missing the acsp magic" do
    bad = :binary.copy(<<0>>, 200)
    assert {:error, %Color.ICC.ParseError{reason: :bad_header}} = Profile.parse(bad)
  end

  test "rejects a non-RGB profile class" do
    profile_binary = build_synthetic_profile()
    # Replace "RGB " with "CMYK"
    <<header_until_cs::binary-size(16), "RGB ", rest::binary>> = profile_binary
    bad = header_until_cs <> "CMYK" <> rest

    assert {:error, %Color.ICC.ParseError{reason: :unsupported_profile}} =
             Profile.parse(bad)
  end

  test "rejects a profile that is missing one of the required tags" do
    # Build a profile with only 5 of the 6 required tags by truncating
    # the tag table count.
    profile_binary = build_synthetic_profile()
    <<header::128-bytes, _count::32, rest::binary>> = profile_binary
    bad = header <> <<5::32>> <> :binary.part(rest, 0, 5 * 12 + byte_size(rest) - 6 * 12)

    assert {:error, %Color.ICC.ParseError{reason: :missing_tag}} = Profile.parse(bad)
  end

  test "load/1 returns File.Error for a missing path" do
    assert {:error, %File.Error{reason: :enoent}} =
             Profile.load("/nonexistent/profile.icc")
  end
end
