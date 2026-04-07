defmodule Color.ParseError do
  @moduledoc """
  Raised when CSS Color Module Level 4 parsing fails. Used by
  `Color.CSS.parse/1`, `Color.CSS.Tokenizer`, and `Color.CSS.Calc`.

  Has fields:

  * `:input` — the original input string, where available.

  * `:function` — the CSS function that was being parsed (`"rgb"`,
    `"oklch"`, `"calc"`, …) or `nil`.

  * `:reason` — a short string describing the failure.

  """

  defexception [:input, :function, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{function: nil, input: nil, reason: reason}) do
    reason
  end

  def message(%__MODULE__{function: function, reason: reason}) when is_binary(function) do
    "#{function}(): #{reason}"
  end

  def message(%__MODULE__{input: input, reason: reason}) when is_binary(input) do
    "#{reason} (in #{inspect(input)})"
  end

  def message(%__MODULE__{reason: reason}) do
    reason
  end
end
