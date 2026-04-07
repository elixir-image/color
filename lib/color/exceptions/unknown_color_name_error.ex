defmodule Color.UnknownColorNameError do
  @moduledoc """
  Raised when a CSS named-color lookup fails.

  Has fields:

  * `:name` — the unknown name (string or atom).

  """

  defexception [:name]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{name: name}) do
    "Unknown CSS color name #{inspect(name)}"
  end
end
