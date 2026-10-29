extends PetState
## DRAGGED: follow the cursor while the left button is held.
## On release: near the taskbar -> SITTING, otherwise fall down and go IDLE.
## The pet can be caught again mid-fall.

@export_range(0.0, 1.0) var complain_chance := 0.35

var _grab_offset := Vector2.ZERO
var _fall_tween: Tween


func enter(msg: Dictionary = {}) -> void:
	_grab_offset = msg.get("grab_offset", Vector2.ZERO)
	pet.play_anim(&"drag")
	if randf() < complain_chance:
		pet.say_random_line(pet.grab_lines)


func exit() -> void:
	_stop_fall()


func update(_delta: float) -> void:
	if _is_falling():
		return
	# Safety net: if the release event was lost (e.g. focus change), drop anyway.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drop()
		return
	pet.global_position = pet.get_global_mouse_position() + _grab_offset
	pet.clamp_to_bounds()


func handle_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if not mb.pressed and not _is_falling():
		_drop()
		get_viewport().set_input_as_handled()
	elif mb.pressed and _is_falling() and pet.contains_point(mb.position):
		# Caught mid-air.
		_stop_fall()
		_grab_offset = pet.global_position - mb.position
		pet.play_anim(&"drag")
		get_viewport().set_input_as_handled()


func _drop() -> void:
	if pet.is_near_floor():
		machine.transition_to(PetStateMachine.SITTING)
		return

	# Free fall: t = sqrt(2h / g), eased-in to fake acceleration.
	var height := pet.floor_y - pet.position.y
	var duration := sqrt(2.0 * height / pet.gravity)
	pet.play_anim(&"fall", &"drag")
	_fall_tween = create_tween()
	_fall_tween.tween_property(pet, "position:y", pet.floor_y, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tween.finished.connect(func() -> void: machine.transition_to(PetStateMachine.IDLE))


func _is_falling() -> bool:
	return _fall_tween != null and _fall_tween.is_valid()


func _stop_fall() -> void:
	if _fall_tween:
		_fall_tween.kill()
		_fall_tween = null
