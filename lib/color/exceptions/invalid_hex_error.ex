defmodule Color.InvalidHexError do
  @moduledoc """
  Raised when a hex color string cannot be parsed.

  Has fields:

  * `:hex` — the offending input string.

  * `:reason` — `:bad_length` (not 3, 4, 6 or 8 hex digits) or
    `:bad_byte` (one or more characters are not hex digits).

  """

  defexception [:hex, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{hex: hex, reason: :bad_length}) do
    "Invalid hex color #{inspect(hex)}: expected 3, 4, 6, or 8 hex digits"
  end

  def message(%__MODULE__{hex: hex, reason: :bad_byte}) do
    "Invalid hex color #{inspect(hex)}: contains non-hex characters"
  end

  def message(%__MODULE__{hex: hex, reason: nil}) do
    "Invalid hex color #{inspect(hex)}"
  end
end
