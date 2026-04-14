defmodule Color.PaletteError do
  @moduledoc """
  Raised when a palette cannot be generated — typically because of
  invalid options (bad stop list, out-of-range anchor, unreachable
  contrast target, etc.).

  Has fields:

  * `:reason` — a short atom describing the failure (e.g.
    `:empty_stops`, `:duplicate_stops`, `:invalid_anchor`,
    `:invalid_seed`, `:unknown_option`).

  * `:detail` — a human-readable string with more context.

  """

  defexception [:reason, :detail]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason, detail: nil}) do
    "Color.PaletteError: #{inspect(reason)}"
  end

  def message(%__MODULE__{reason: reason, detail: detail}) do
    "Color.PaletteError: #{inspect(reason)} — #{detail}"
  end
end
