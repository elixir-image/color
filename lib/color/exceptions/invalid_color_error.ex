defmodule Color.InvalidColorError do
  @moduledoc """
  Raised when `Color.new/1,2` cannot interpret its input as a color.

  Has fields:

  * `:value` — the input that could not be interpreted.

  * `:space` — the color space that was being constructed (or `nil`
    when the input failed before a space could be selected).

  * `:reason` — a short string describing why.

  """

  defexception [:value, :space, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{value: value, space: nil, reason: reason}) do
    "Cannot build a color from #{inspect(value)}: #{reason}"
  end

  def message(%__MODULE__{value: value, space: space, reason: reason}) do
    "Cannot build a #{space} color from #{inspect(value)}: #{reason}"
  end
end
