class_name PetGestures
extends Node
## Turns left-button input on the pet into gestures. A press only becomes a pickup once
## the cursor moves past drag_distance or the button is held for hold_time; a quick
## press and release is a click, and a second click soon after is a double-click.
## A press on her head that then moves mostly sideways is a headpat instead of a pickup:
## every change of direction while rubbing counts as one stroke.
## A single click is reported once double_click_time has passed without a second one,
## so a double-click never also counts as a click.
## Fed by PetState.handle_input, so states that handle the mouse themselves (Dragged)
## simply don't pass events on.

## The press turned into a pickup. `press_position` is where the button went down.
signal drag_started(press_position: Vector2)
signal clicked(position: Vector2)
signal double_clicked(position: Vector2)
signal pat_started
## One back-and-forth stroke of a headpat.
signal patted
signal pat_ended

## Pixels the cursor may move while pressed and still count as a click.
@export var drag_distance := 6.0
## Holding the button this long without moving picks her up.
@export var hold_time := 0.2
## Windows' default double-click time; reading the user's own setting would need Win32.
@export var double_click_time := 0.5
## How far the cursor must travel back before a rub counts as a new stroke.
@export var stroke_distance := 10.0
## A head press becomes a pat when the first movement is at least this much more
## sideways than vertical.
@export var pat_sideways_ratio := 1.2

var _pressing := false
var _press_position := Vector2.ZERO
var _press_part := &""
var _held := 0.0
## The current press is the second half of a double-click.
var _second_press := false
## A finished click that may still become the first half of a double-click.
var _pending_click := false
var _pending_position := Vector2.ZERO
var _pending_left := 0.0
var _patting := false
## While patting: which way the cursor is rubbing (-1 / 1) and how far it got that way.
var _pat_direction := 0.0
var _pat_extreme_x := 0.0

@onready var _pet := get_parent() as DesktopPet


## Returns true if the event was part of a gesture on the pet (mark it handled).
func handle_input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and _pet.contains_point(mb.position):
			_begin_press(mb.position)
			return true
		if not mb.pressed and _patting:
			_end_pat()
			return true
		if not mb.pressed and _pressing:
			_pressing = false
			_finish_click(mb.position)
			return true
		return false
	var motion := event as InputEventMouseMotion
	if motion == null:
		return false
	if _patting:
		_track_pat(motion.position.x)
		return true
	if _pressing and motion.position.distance_to(_press_position) > drag_distance:
		var moved := motion.position - _press_position
		if _press_part == &"head" and absf(moved.x) >= absf(moved.y) * pat_sideways_ratio:
			_begin_pat(motion.position.x)
		else:
			_start_drag()
		return true
	return false


func is_patting() -> bool:
	return _patting


## Forgets the press in progress and any click waiting for a second one.
func cancel() -> void:
	_pressing = false
	_second_press = false
	_pending_click = false
	if _patting:
		_end_pat()


func _process(delta: float) -> void:
	if _pending_click:
		_pending_left -= delta
		if _pending_left <= 0.0:
			_pending_click = false
			clicked.emit(_pending_position)
	if not (_pressing or _patting):
		return
	# Safety net: if the release was lost (e.g. focus change), drop the press.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cancel()
		return
	if _patting:
		return
	_held += delta
	if _held >= hold_time:
		_start_drag()


func _begin_press(position: Vector2) -> void:
	_pressing = true
	_press_position = position
	_press_part = _pet.get_body_part(position)
	_held = 0.0
	_second_press = _pending_click and position.distance_to(_pending_position) <= drag_distance
	if _pending_click and not _second_press:
		# Clicked somewhere else on her: the earlier click stands on its own.
		clicked.emit(_pending_position)
	_pending_click = false


func _finish_click(position: Vector2) -> void:
	if _second_press:
		_second_press = false
		double_clicked.emit(position)
		return
	_pending_click = true
	_pending_position = position
	_pending_left = double_click_time


func _start_drag() -> void:
	var press_position := _press_position
	cancel()
	drag_started.emit(press_position)


func _begin_pat(x: float) -> void:
	_pressing = false
	_second_press = false
	_patting = true
	_pat_direction = signf(x - _press_position.x)
	_pat_extreme_x = x
	pat_started.emit()


func _track_pat(x: float) -> void:
	if (x - _pat_extreme_x) * _pat_direction > 0.0:
		_pat_extreme_x = x # Still rubbing the same way.
	elif absf(x - _pat_extreme_x) >= stroke_distance:
		_pat_direction = -_pat_direction
		_pat_extreme_x = x
		patted.emit()


func _end_pat() -> void:
	_patting = false
	pat_ended.emit()
