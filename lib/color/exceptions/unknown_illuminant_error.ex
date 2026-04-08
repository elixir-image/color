defmodule Color.UnknownIlluminantError do
  @moduledoc """
  Raised when an illuminant atom is not recognised by
  `Color.Tristimulus`.

  Has fields:

  * `:illuminant` — the offending value.

  * `:observer_angle` — the observer angle (`2` or `10`), if known.

  * `:valid` — the list of valid illuminant atoms, when supplied.

  """

  defexception [:illuminant, :observer_angle, valid: nil]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{illuminant: illuminant, observer_angle: nil, valid: nil}) do
    "Unknown illuminant #{inspect(illuminant)}"
  end

  def message(%__MODULE__{illuminant: illuminant, observer_angle: angle, valid: nil}) do
    "Unknown illuminant #{inspect(illuminant)} for #{inspect(angle)}° observer"
  end

  def message(%__MODULE__{illuminant: illuminant, observer_angle: nil, valid: valid}) do
    "Unknown illuminant #{inspect(illuminant)}. Valid illuminants are #{inspect(valid)}"
  end

  def message(%__MODULE__{illuminant: illuminant, observer_angle: angle, valid: valid}) do
    "Unknown illuminant #{inspect(illuminant)} for #{inspect(angle)}° observer. " <>
      "Valid illuminants are #{inspect(valid)}"
  end
end
