extends Camera3D
## What the camera adds to the walk, for the eye only: the view dips a little at every step (head bob), and it
## widens for a moment when a door bursts open (FOV kick).
## It moves this camera inside the head and nothing else. The player's body, its collider and its head (the yaw and the
## pitch that steer the walk) never see it, so the effects cannot change where the player goes.
## The bob follows the footsteps: the view is lowest when a foot comes down and highest halfway to the next step.

const Feel := preload("feel.gd")
const Footsteps := preload("footsteps.gd")
const FEEL: Feel = preload("feel.tres")

@export var footsteps: Footsteps ## Where the step cycle comes from.
@export var head_bob := true ## Off: the camera stays exactly where the head is. Head bob makes some players sick, so it can be turned off.
@export var fov_kick := true ## Off: the view keeps its field of view. A comfort setting like the head bob.

var _bob := 0.0 ## 0 standing, 1 walking, eased in between so the bob fades in and out.
var _kick: Tween
@onready var _rest_fov := fov ## The field of view without a kick: the scene's.

## A door bursts open: the view widens fast and eases back slowly, the follow-through of the push.
## A tween runs on the frame time, so the kick takes as long at any frame rate.
func kick() -> void:
	if not fov_kick:
		return
	if _kick != null:
		_kick.kill()
	_kick = create_tween()
	_kick.tween_property(self, "fov", _rest_fov + FEEL.kick_degrees, FEEL.kick_out_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_kick.tween_property(self, "fov", _rest_fov, FEEL.kick_back_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(delta: float) -> void:
	if not fov_kick and fov != _rest_fov: # turned off in the middle of a kick
		if _kick != null:
			_kick.kill()
		fov = _rest_fov
	if not head_bob:
		_bob = 0.0
		position = Vector3.ZERO
		return
	var target := 1.0 if footsteps.walking else 0.0
	_bob += (target - _bob) * (1.0 - exp(-FEEL.bob_smoothing * delta)) # the same fade at any frame rate
	var cycle := footsteps.distance / FEEL.stride # 0 as a foot comes down, 1 at the next one
	position = Vector3(0.0, -FEEL.bob_height * _bob * (1.0 + cos(TAU * cycle)) / 2.0, 0.0)
