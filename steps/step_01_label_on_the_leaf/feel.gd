extends Resource
## How walking feels: the numbers of the footsteps, the head bob and the FOV kick. One data file (feel.tres), tuned in the inspector and never in code.
## Measured against the rooms and the player: the player walks 5 m a second, a room is 10 to 18 m long.

@export var stride := 1.7 ## Metres per step. At 5 m a second that is three steps a second, the pace of a jog: six steps cross a 10 m room.
@export_range(0.0, 1.0) var first_step := 0.5 ## At the start of a run the first step comes after this part of a stride (0.85 m, a sixth of a second).
@export_range(0.0, 0.05) var bob_height := 0.025 ## Metres the view dips at every step, and only down and up: no roll, no sway, the horizon stays level.
@export var bob_smoothing := 8.0 ## How fast the bob fades in when the walk starts and out when it stops, per second (two thirds of the way in an eighth of a second).
@export_range(0.0, 2.5) var kick_degrees := 2.0 ## How much wider the view gets when a door bursts open. The camera's 75 degrees (vertical) are 107.5 across a 16:9 screen; 2.5 more would reach 110, the widest view a comfortable game offers.
@export var kick_out_time := 0.12 ## Seconds to widen: fast, it is the push.
@export var kick_back_time := 0.45 ## Seconds to ease back: slow, so the view never pumps.
