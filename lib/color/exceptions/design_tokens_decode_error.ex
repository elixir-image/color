defmodule Color.DesignTokensDecodeError do
  @moduledoc """
  Raised (or returned) when a Design Tokens (DTCG 2025.10) token
  cannot be decoded into a `Color.*` struct.

  Has fields:

  * `:reason` — short atom describing the failure (e.g.
    `:unknown_color_space`, `:missing_field`, `:bad_components`,
    `:bad_alpha`, `:bad_hex`, `:not_a_color_token`).

  * `:detail` — human-readable context string.

  """

  defexception [:reason, :detail]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason, detail: nil}) do
    "Color.DesignTokensDecodeError: #{inspect(reason)}"
  end

  def message(%__MODULE__{reason: reason, detail: detail}) do
    "Color.DesignTokensDecodeError: #{inspect(reason)} — #{detail}"
  end
end
