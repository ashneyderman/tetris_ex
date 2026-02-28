1. Need robot that knows how to play tetris.

Given the instance of the game some up with a sequence of moves that would maximize the score.

What are the possible moves:

{:rotate, :cw}, {:rotate, :ccw}, {:shift, :left}, {:shift, :right}, :drop_shape, :capture_shape

# Here is a sample game transcript:

{:game, <time_offset>, :new, :s, {5, -1}}
{:user, <time_offset>, :shift, :left}
{:user, <time_offset>, :rotate, :cw}
{:user, <time_offset>, :drop_shape}
{:game, <time_offset>, :new, :s_mirrored, {5, -1}},
{:user, <time_offset>, :shift, :left}
{:user, <time_offset>, :shift, :left}
{:user, <time_offset>, :shift, :left}
{:game, <time_offset>, :capture_shape}

2. We need transcript capabilities: similar to how chess games are recorded.
