defmodule Color.MissingWorkingSpaceError do
  @moduledoc """
  Raised when `Color.convert/2` is called with `Color.RGB` as the
  target. Linear `Color.RGB` requires a named working space, supplied
  via `Color.convert/3` or `convert/4`.

  """

  defexception target: Color.RGB

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{}) do
    "Color.RGB requires a working space. Use Color.convert(color, Color.RGB, :SRGB) " <>
      "or similar."
  end
end
