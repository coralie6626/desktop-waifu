extends PetState
## PERCHED: sitting on the title bar of another app's window (msg: {"window_id": int}).
## Follows the window when it moves; falls off when it's closed, minimized or moved
## somewhere she can't sit.

## How often to re-check where the window is, in seconds.
@export var poll_interval := 0.1
@export_range(0.0, 1.0) var talk_chance := 0.5
@export var perch_lines: PackedStringArray = [
	"Nice view from up here!",
	"This window is comfy~",
	"Don't close this one, okay?",
]

var _window_id := 0
## Feet position relative to the window's left edge, so she rides along when it moves.
var _offset_x := 0.0
var _poll_left := 0.0


func enter(msg: Dictionary = {}) -> void:
	_window_id = msg.get("window_id", 0)
	var window := pet.window_tracker.find_window(_window_id)
	if window.is_empty():
		_fall_off.call_deferred()
		return
	var rect: Rect2 = window.rect
	_offset_x = pet.position.x - rect.position.x
	pet.position.y = rect.position.y
	pet.play_anim(&"sit")
	_poll_left = poll_interval
	pet.window_tracker.updated.connect(_on_windows_updated)
	if randf() < talk_chance:
		pet.say_random_line(perch_lines)


func exit() -> void:
	if pet.window_tracker.updated.is_connected(_on_windows_updated):
		pet.window_tracker.updated.disconnect(_on_windows_updated)


func update(delta: float) -> void:
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = poll_interval
		pet.window_tracker.request_update()


func _on_windows_updated() -> void:
	var window := pet.window_tracker.find_window(_window_id)
	if window.is_empty():
		_fall_off()
		return
	var rect: Rect2 = window.rect
	var top_range := pet.perch_top_range()
	var x := rect.position.x + _offset_x
	if rect.position.y < top_range.x or rect.position.y > top_range.y \
			or x < rect.position.x + pet.perch_margin or x > rect.end.x - pet.perch_margin:
		_fall_off()
		return
	pet.position = Vector2(x, rect.position.y)


func _fall_off() -> void:
	if is_active():
		machine.transition_to(PetStateMachine.DRAGGED, {"falling": true})
