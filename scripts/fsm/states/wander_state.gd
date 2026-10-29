extends PetState
## WANDER: walk left/right along the taskbar edge, turning around at the screen edges.

@export var min_duration := 2.5
@export var max_duration := 6.0

var _direction := 1.0
var _time_left := 0.0


func enter(_msg: Dictionary = {}) -> void:
	_time_left = randf_range(min_duration, max_duration)
	_direction = -1.0 if randf() < 0.5 else 1.0
	pet.face(_direction)
	pet.play_anim(&"walk")


func update(delta: float) -> void:
	pet.position.x += _direction * pet.walk_speed * delta

	# Bounce off the left/right screen edges.
	var half_width := pet.get_hit_rect().size.x * 0.5
	var left := pet.bounds.position.x + half_width
	var right := pet.bounds.end.x - half_width
	if pet.position.x <= left:
		pet.position.x = left
		_direction = 1.0
		pet.face(_direction)
	elif pet.position.x >= right:
		pet.position.x = right
		_direction = -1.0
		pet.face(_direction)

	_time_left -= delta
	if _time_left <= 0.0:
		machine.transition_to(PetStateMachine.IDLE)
