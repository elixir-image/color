defmodule Color.Behaviour do
  @moduledoc """
  Behaviour implemented by every color-space struct module in the
  library.

  Every space — `Color.SRGB`, `Color.Lab`, `Color.Oklch`,
  `Color.JzAzBz`, `Color.YCbCr`, and so on — implements:

  * `to_xyz/1`, which takes a struct of the implementing module and
    returns `{:ok, %Color.XYZ{}}`.

  * `from_xyz/1`, which takes a `%Color.XYZ{}` and returns
    `{:ok, struct}` for the implementing module.

  The hub module `Color` uses these two callbacks to perform any-to-any
  conversion: every `convert/2,3,4` call goes `source → XYZ → target`.

  A struct module that implements this behaviour is guaranteed to
  round-trip losslessly through `Color.XYZ` up to floating-point
  precision (ignoring irreversible gamut changes). Some modules
  additionally accept options on `to_xyz/2` or `from_xyz/2` — the
  behaviour's single-arity callbacks represent the common core.

  """

  @typedoc "The shape of any color-space struct returned by this library."
  @type color :: struct()

  @doc """
  Converts a color of the implementing module's struct type to
  `Color.XYZ`.
  """
  @callback to_xyz(color()) :: {:ok, Color.XYZ.t()} | {:error, Exception.t()}

  @doc """
  Converts a `Color.XYZ` struct to the implementing module's struct
  type.
  """
  @callback from_xyz(Color.XYZ.t()) :: {:ok, color()} | {:error, Exception.t()}
end
