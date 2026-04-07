defmodule Color.UnsupportedTargetError do
  @moduledoc """
  Raised when `Color.convert/2,3,4` is called with a target module
  that is not part of the supported color-space hub.

  Has fields:

  * `:target` — the unsupported target module.

  """

  defexception [:target]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{target: target}) do
    "Unsupported target color module #{inspect(target)}"
  end
end
