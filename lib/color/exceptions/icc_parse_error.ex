defmodule Color.ICC.ParseError do
  @moduledoc """
  Raised when `Color.ICC.Profile.load/1` or `parse/1` cannot interpret
  an ICC profile.

  Has fields:

  * `:reason` — a short atom describing the failure category:

    * `:too_short` — the binary is shorter than the 128-byte ICC
      header.

    * `:bad_header` — the header magic `acsp` is missing or the
      header fields are malformed.

    * `:no_tag_table` — the tag count is zero or missing.

    * `:truncated_tag_table` — the tag table is shorter than its
      declared count.

    * `:unsupported_profile` — the profile is structurally valid
      but is not a matrix-RGB-XYZ profile that this minimal reader
      supports.

    * `:missing_tag` — one of the required `rXYZ`, `gXYZ`, `bXYZ`,
      `rTRC`, `gTRC`, `bTRC` tags is absent.

    * `:bad_xyz_tag`, `:bad_trc_tag` — a tag is the wrong type or
      length.

  * `:details` — extra context (the missing tag name, the parsed
    header map, etc.).

  """

  defexception [:reason, :details]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :too_short}) do
    "ICC profile is shorter than the 128-byte header"
  end

  def message(%__MODULE__{reason: :bad_header}) do
    "ICC profile header is malformed (missing 'acsp' magic or wrong field layout)"
  end

  def message(%__MODULE__{reason: :no_tag_table}) do
    "ICC profile has no tag table"
  end

  def message(%__MODULE__{reason: :truncated_tag_table}) do
    "ICC profile tag table is shorter than its declared count"
  end

  def message(%__MODULE__{reason: :unsupported_profile, details: details}) do
    "ICC profile is not a matrix RGB→XYZ profile (got #{inspect(details)})"
  end

  def message(%__MODULE__{reason: :missing_tag, details: tag}) do
    "ICC profile is missing required tag #{inspect(tag)}"
  end

  def message(%__MODULE__{reason: :bad_xyz_tag}) do
    "ICC profile XYZ tag is malformed"
  end

  def message(%__MODULE__{reason: :bad_trc_tag}) do
    "ICC profile TRC tag is malformed"
  end

  def message(%__MODULE__{reason: reason}) do
    "ICC profile parse error: #{inspect(reason)}"
  end
end
