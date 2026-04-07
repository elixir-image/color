defmodule Color.UnknownBlendModeError do
  @moduledoc """
  Raised when `Color.Blend.blend/3` is called with an unknown blend
  mode.

  Has fields:

  * `:mode` — the unknown mode.

  * `:valid` — the list of supported modes.

  """

  defexception [:mode, valid: nil]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{mode: mode, valid: nil}) do
    "Unknown blend mode #{inspect(mode)}"
  end

  def message(%__MODULE__{mode: mode, valid: valid}) do
    "Unknown blend mode #{inspect(mode)}. Valid modes are #{inspect(valid)}"
  end
end
