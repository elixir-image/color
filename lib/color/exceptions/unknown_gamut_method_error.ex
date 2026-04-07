defmodule Color.UnknownGamutMethodError do
  @moduledoc """
  Raised when `Color.Gamut.to_gamut/3` is called with an unknown
  gamut-mapping method.

  Has fields:

  * `:method` — the unknown method.

  * `:valid` — the list of supported methods.

  """

  defexception [:method, valid: nil]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{method: method, valid: nil}) do
    "Unknown gamut mapping method #{inspect(method)}"
  end

  def message(%__MODULE__{method: method, valid: valid}) do
    "Unknown gamut mapping method #{inspect(method)}. Valid methods are #{inspect(valid)}"
  end
end
