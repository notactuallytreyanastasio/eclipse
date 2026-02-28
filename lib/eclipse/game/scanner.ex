defmodule Eclipse.Game.Scanner do
  @moduledoc """
  The scanner line that sweeps left-to-right across the board,
  clearing any marked tiles it passes over.
  """

  @type t :: %__MODULE__{
          position: float(),
          speed: float(),
          active?: boolean()
        }

  defstruct position: 0.0, speed: 0.0625, active?: true

  @spec advance(t(), non_neg_integer()) :: {t(), non_neg_integer(), non_neg_integer()}
  def advance(%__MODULE__{position: pos, speed: speed} = scanner, board_width) do
    old_col = trunc(pos)
    new_pos = pos + speed

    {wrapped_pos, from_col, to_col} =
      if new_pos >= board_width do
        {new_pos - board_width, old_col, board_width - 1}
      else
        new_col = trunc(new_pos)

        if new_col > old_col do
          {new_pos, old_col, new_col - 1}
        else
          {new_pos, -1, -1}
        end
      end

    {%{scanner | position: wrapped_pos}, from_col, to_col}
  end
end
