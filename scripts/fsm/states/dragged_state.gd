extends PetState
## DRAGGED: follow the cursor while the left button is held.
## On release: over a window's title bar -> fall onto it and go PERCHED; near the
## taskbar -> SITTING; otherwise fall down and go IDLE. The pet can be caught again mid-fall.
## Entered with {"falling": true} (e.g. her window was closed), she starts falling at once.

@export_range(0.0, 1.0) var complain_chance := 0.35
## How often to refresh the window snapshot while held, so the drop target is current.
@export var window_poll_interval := 0.25

var _grab_offset := Vector2.ZERO
var _fall_tween: Tween
var _poll_left := 0.0
## Set while a {"falling": true} drop waits for the deferred call (the mouse may be held,
## e.g. dragging the window she sat on, so she must not follow the cursor meanwhile).
var _drop_queued := false


func enter(msg: Dictionary = {}) -> void:
	_grab_offset = msg.get("grab_offset", Vector2.ZERO)
	_poll_left = 0.0
	pet.stop_reaction()
	if msg.get("falling", false):
		# Deferred so we don't start another transition from inside this one.
		_drop_queued = true
		_drop.call_deferred()
		return
	pet.play_anim(&"drag")
	if randf() < complain_chance:
		pet.say_random_line(pet.grab_lines)


func exit() -> void:
	_stop_fall()


func update(delta: float) -> void:
	if _is_falling() or _drop_queued:
		return
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = window_poll_interval
		pet.window_tracker.request_update()
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

	if _drop_queued:
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
	_drop_queued = false
	if not is_active():
		return
	var perch := pet.find_perch()
	if not perch.is_empty():
		var id: int = perch.id
		_fall_to(perch.rect.position.y, func() -> void:
			machine.transition_to(PetStateMachine.PERCHED, {"window_id": id}))
		return
	if pet.is_near_floor():
		machine.transition_to(PetStateMachine.SITTING)
		return
	_fall_to(pet.floor_y, func() -> void: machine.transition_to(PetStateMachine.IDLE))


## Free fall: t = sqrt(2h / g), eased-in to fake acceleration. A target at or above the
## feet (dropped right onto a title bar) is snapped to instead.
func _fall_to(target_y: float, on_landed: Callable) -> void:
	var height := target_y - pet.position.y
	if height <= 1.0:
		pet.position.y = target_y
		on_landed.call()
		return
	var duration := sqrt(2.0 * height / pet.gravity)
	pet.play_anim(&"fall", &"drag")
	_fall_tween = create_tween()
	_fall_tween.tween_property(pet, "position:y", target_y, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tween.finished.connect(on_landed)


func _is_falling() -> bool:
	return _fall_tween != null and _fall_tween.is_valid()


func _stop_fall() -> void:
	if _fall_tween:
		_fall_tween.kill()
		_fall_tween = null
