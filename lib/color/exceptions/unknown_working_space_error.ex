defmodule Color.UnknownWorkingSpaceError do
  @moduledoc """
  Raised when an RGB working-space identifier or its CSS Color 4 name
  is not recognised.

  Has fields:

  * `:working_space` — the unknown identifier.

  * `:valid` — the list of valid identifiers, when known.

  """

  defexception [:working_space, valid: nil]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{working_space: ws, valid: nil}) do
    "Unknown RGB working space #{inspect(ws)}"
  end

  def message(%__MODULE__{working_space: ws, valid: valid}) do
    "Unknown RGB working space #{inspect(ws)}. Valid spaces are #{inspect(valid)}"
  end
end
