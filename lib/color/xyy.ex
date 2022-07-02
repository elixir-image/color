defmodule Color.XYY do
  defstruct [
    x: nil,
    y: nil,
    yY: 1.0
  ]

  def to_xyz(%__MODULE__{x: x, y: y, yY: yY}) do
    [xi, yi, zi] = to_xyz([x, y, yY])

    %Color.XYZ{x: xi, y: yi, z: zi}
  end

  def to_xyz(["_", "_"]) do
    nil
  end

  def to_xyz([x, y]) do
    to_xyz([x, y, 1.0])
  end

  def to_xyz([x, y, yY]) do
    xi = x * yY / y
    yi = yY
    zi = ((1.0 - x - y) * yY) / y

    [xi, yi, zi]
  end

  def to_xyz_tensor(["_", "_"]) do
    nil
  end

  def to_xyz_tensor(list) do
    list
    |> to_xyz()
    |> Nx.tensor()
  end

end