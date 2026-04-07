defmodule Color.InvalidComponentError do
  @moduledoc """
  Raised when one or more channel values fall outside the legal range
  for a color space, are the wrong numeric type, or contain `NaN` /
  infinity.

  Has fields:

  * `:space` — the color space being constructed (a short atom like
    `:srgb` or a friendly label like `"Lab"`).

  * `:value` — the offending list (or single value).

  * `:range` — a `{lo, hi}` tuple naming the legal range, when
    applicable. `nil` for type-mismatch or NaN errors.

  * `:reason` — `:out_of_range`, `:mixed_types`, `:not_numeric`,
    `:integers_not_allowed`, `:nan`, or `:infinity`.

  """

  defexception [:space, :value, :range, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{space: space, value: value, reason: :out_of_range, range: {lo, hi}}) do
    "#{space} channel out of #{format_range(lo, hi)} range: #{inspect(value)}"
  end

  def message(%__MODULE__{space: space, value: value, reason: :mixed_types}) do
    "#{space} list must be all floats or all integers, not a mix: #{inspect(value)}"
  end

  def message(%__MODULE__{space: space, value: value, reason: :not_numeric}) do
    "#{space} list must contain only numbers: #{inspect(value)}"
  end

  def message(%__MODULE__{space: space, value: value, reason: :integers_not_allowed}) do
    "#{space} expects a list of floats, not integers: #{inspect(value)}"
  end

  def message(%__MODULE__{space: space, value: value, reason: :floats_required}) do
    "#{space} list must contain only floats: #{inspect(value)}"
  end

  def message(%__MODULE__{space: space, value: value, reason: :nan}) do
    "#{space} list contains NaN: #{inspect(value)}"
  end

  def message(%__MODULE__{space: space, value: value, reason: :infinity}) do
    "#{space} list contains infinity: #{inspect(value)}"
  end

  def message(%__MODULE__{space: space, value: value, reason: :wrong_count}) do
    "#{space} list has the wrong number of components: #{inspect(value)}"
  end

  defp format_range(lo, hi) when is_integer(lo) and is_integer(hi), do: "#{lo}..#{hi}"
  defp format_range(lo, hi), do: "[#{lo}, #{hi}]"
end
