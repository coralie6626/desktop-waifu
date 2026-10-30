class_name WindowDodger
extends Node
## Keeps her out of the way while you drag a window across her: when a window that's
## moving overlaps her, she fades out almost completely (and doesn't block the view),
## then fades back in once it's gone or has stopped. While she's dodging, the window
## list is refreshed quickly so she reacts in time.

## Opacity while dodging.
@export var faded_alpha := 0.15
## Seconds without a moving window over her before she comes back.
@export var return_after := 0.8
## Seconds between window checks while dodging.
@export var fast_poll := 0.25

var dodging := false

var _previous: Dictionary = {} # window id -> rect, from the last snapshot.
var _clear_for := 0.0
var _poll_left := 0.0
var _tween: Tween

@onready var _pet := get_parent() as DesktopPet
@onready var _tracker: WindowTracker = $"../WindowTracker"


func _ready() -> void:
	_tracker.updated.connect(_on_windows_updated)


func _process(delta: float) -> void:
	if not dodging:
		return
	_clear_for += delta
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = fast_poll
		_tracker.request_update()
	if _clear_for >= return_after:
		_set_dodging(false)


## Which windows moved since the last snapshot and now overlap `hit` (ignoring `skip_id`,
## the window she's sitting on, which she moves with).
static func moving_over(windows: Array[Dictionary], previous: Dictionary, hit: Rect2, skip_id: int) -> bool:
	for window in windows:
		if window.id == skip_id or not previous.has(window.id):
			continue
		var rect: Rect2 = window.rect
		if rect.position != previous[window.id].position and rect.intersects(hit):
			return true
	return false


func _on_windows_updated() -> void:
	var state := _pet.state_machine.current_state
	var skip := -1
	if state and state.name == PetStateMachine.PERCHED:
		skip = state.get(&"_window_id")
	if _pet.visible and moving_over(_tracker.windows, _previous, _pet.get_hit_rect(), skip):
		_clear_for = 0.0
		_set_dodging(true)
	_previous.clear()
	for window in _tracker.windows:
		_previous[window.id] = window.rect


func _set_dodging(on: bool) -> void:
	if on == dodging:
		return
	dodging = on
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_pet, "modulate:a", faded_alpha if on else 1.0, 0.15)
