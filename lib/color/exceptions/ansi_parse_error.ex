defmodule Color.ANSI.ParseError do
  @moduledoc """
  Raised when `Color.ANSI.parse/1` cannot interpret an ANSI SGR
  escape sequence.

  Has fields:

  * `:sequence` — the offending input binary.

  * `:reason` — a short atom describing the failure:

    * `:no_csi` — the input does not start with `ESC [`.

    * `:no_terminator` — the sequence has no closing `m`.

    * `:no_colour_param` — the sequence has a CSI and terminator
      but no colour parameter (e.g. `\\e[0m` reset, `\\e[1m` bold,
      `\\e[39m` default-foreground).

    * `:bad_index` — a 256-colour index (`38;5;N`) is out of range
      or not a valid integer.

    * `:bad_rgb` — a truecolor R/G/B triple is out of range or not
      valid integers.

  """

  defexception [:sequence, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{sequence: sequence, reason: :no_csi}) do
    "ANSI sequence does not start with ESC[: #{inspect(sequence)}"
  end

  def message(%__MODULE__{sequence: sequence, reason: :no_terminator}) do
    "ANSI sequence has no closing `m`: #{inspect(sequence)}"
  end

  def message(%__MODULE__{sequence: sequence, reason: :no_colour_param}) do
    "ANSI sequence contains no colour parameter: #{inspect(sequence)}"
  end

  def message(%__MODULE__{sequence: sequence, reason: :bad_index}) do
    "ANSI sequence has an invalid 256-colour index: #{inspect(sequence)}"
  end

  def message(%__MODULE__{sequence: sequence, reason: :bad_rgb}) do
    "ANSI sequence has an invalid truecolor R;G;B triple: #{inspect(sequence)}"
  end

  def message(%__MODULE__{sequence: sequence, reason: reason}) do
    "ANSI parse error (#{inspect(reason)}): #{inspect(sequence)}"
  end
end
