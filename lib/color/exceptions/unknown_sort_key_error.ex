defmodule Color.UnknownSortKeyError do
  @moduledoc """
  Raised when `Color.sort/2` is called with a `:by` value that is
  neither a recognised preset atom nor a 1-arity function.

  Has fields:

  * `:key` — the unrecognised value.

  * `:valid` — the list of supported preset atoms.

  """

  defexception [:key, valid: nil]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{key: key, valid: nil}) do
    "Unknown sort key #{inspect(key)}"
  end

  def message(%__MODULE__{key: key, valid: valid}) do
    "Unknown sort key #{inspect(key)}. Valid keys are #{inspect(valid)} " <>
      "or a 1-arity function."
  end
end
