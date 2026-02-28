1. Need robot that knows how to play tetris.

Given the  instance of the game some up with a sequence of moves that would maximize the score.

What are the possible moves:

{:rotate, :cw}, {:rotate, :ccw}, 
{:shift, :left}, {:shift, :right},
:drop_shape

Here is a sample game transcript:

Game            |  User
-------------------------
:new_s          | 
                | :s_l
                | :r_cw
                | :ds
:new_s_mirrored | 
                | :s_l
                | :s_l
                | :s_l
:tick           |
:over           |

2. We need transcript capabilities: similar to how chess games are recorded.
