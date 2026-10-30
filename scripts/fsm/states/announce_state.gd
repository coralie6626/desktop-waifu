extends PetState
## ANNOUNCE: something is due (see PetAnnouncer). Walk to the middle of the taskbar,
## then let the announcer show it; it sends her back to IDLE once it's dismissed.

## Walks a bit faster than usual: she has news.
@export var speed_scale := 1.5

var _target_x := 0.0
var _walking := false


func enter(_msg: Dictionary = {}) -> void:
	pet.position.y = pet.floor_y
	_target_x = pet.bounds.get_center().x
	_walking = absf(_target_x - pet.position.x) > 1.0
	if _walking:
		pet.face(signf(_target_x - pet.position.x))
		pet.play_anim(&"walk")
	else:
		_arrive.call_deferred()


func exit() -> void:
	if _walking:
		pet.announcer.abort()


func update(delta: float) -> void:
	if not _walking:
		return
	pet.position.x = move_toward(pet.position.x, _target_x, pet.walk_speed * speed_scale * delta)
	if is_equal_approx(pet.position.x, _target_x):
		_walking = false
		_arrive()


func _arrive() -> void:
	if not is_active():
		return
	pet.play_anim(&"idle")
	pet.announcer.show_next()
