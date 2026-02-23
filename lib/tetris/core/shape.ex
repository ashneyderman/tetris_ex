defmodule Tetris.Core.Shape do
  @moduledoc """
  This module defines methods and structures that manipulate tetris shapes.

  Here is an example of the basic tetris shape (* - cell that is on,
  o - center of rotation)

   ^ y
   |
   |
   * *
   o-------------------->x
   *

     (1, 1)
     (0, 1)
     (0, 0)
     (0,-1)

  The shape is a list of coordinates occupied by non-empty cells. To
  rotate the shape then we need to perform geometric transformation of
  the shape's coordinates. In math terms such transformation translates
  to multiplication of coordinate matrix shown above by rotation transform
  matrix below:

    (cos t, -sin t)
    (sin t,  cos t)

  where t is the angle by which we rotate. For example, to rotate the
  shape by 90 degrees clock-wise the transformation matrix becomes:

    (0, -1)
    (1,  0)

  Shifting the shape by some delta along x and y axis can be done
  in a similar manner.

  Note that shape coordinates might contain numbers that end in .5.
  That is done in the interest of making shapes to rotate around their
  natural center. The shape is usually manipulated within the context
  of a `Field`. The cell coordinates in that field are integers,
  therefore some of the operations of this module will have
  `:snap_to_field` option to help ease of translation between shapes
  and the field they are manipulated within.
  """

  alias Tetris.Core.Shape

  @type rotation :: :cw | :ccw

  @type label :: atom()

  @type t :: %__MODULE__{
          label: label() | nil,
          coords: Matrix.matrix()
        }

  defstruct label: nil,
            coords: []

  @doc """
  Rotates the shape.

  The angle of rotation is always 90 (pi/2) degrees either clock-wise with
  `:cw` parameter or -90 (-pi/2) degrees counter clock-wise with `:ccw`
  parameter.
  """
  @spec rotate(Shape.t(), rotation()) :: Shape.t()
  def rotate(%Shape{} = shape, :cw) do
    do_rotate(shape, :math.pi() / 2)
  end

  def rotate(%Shape{} = shape, :ccw) do
    do_rotate(shape, -1 * (:math.pi() / 2))
  end

  # why are we not snapping these?
  @spec do_rotate(Shape.t(), float()) :: Shape.t()
  defp do_rotate(%Shape{coords: coords} = shape, angle) do
    c00 = :math.cos(angle) |> round
    c01 = (:math.sin(angle) |> round) * -1
    c10 = :math.sin(angle) |> round
    c11 = :math.cos(angle) |> round
    rotation = [[c00, c01], [c10, c11]]
    new_coords = Matrix.mult(coords, rotation)
    %Shape{shape | coords: new_coords}
  end

end
