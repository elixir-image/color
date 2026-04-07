defmodule Color.UnknownColorSpaceError do
  @moduledoc """
  Raised when an atom or module passed as a color-space identifier is
  not recognised.

  Has fields:

  * `:space` — the unknown identifier.

  """

  defexception [:space]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{space: space}) do
    "Unknown color space #{inspect(space)}"
  end
end
