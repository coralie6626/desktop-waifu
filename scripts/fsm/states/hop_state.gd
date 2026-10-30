extends PetState
## HOP: a little jump from the taskbar up onto a window's title bar
## (msg: {"window_id": int, "target": Vector2}), then PERCHED there. If the window is
## gone by the time she lands, she falls back down.

## Seconds the jump takes.
@export var duration := 0.7
## How far above the higher end the arc peaks, in pixels.
@export var arc_height := 70.0

var _window_id := 0
var _tween: Tween


func enter(msg: Dictionary = {}) -> void:
	_window_id = msg.get("window_id", 0)
	var start := pet.position
	var target: Vector2 = msg.get("target", start)
	var peak := minf(start.y, target.y) - arc_height
	pet.face(signf(target.x - start.x))
	pet.play_anim(&"fall", &"drag")
	pet.say_line(&"hop")
	_tween = create_tween()
	_tween.tween_method(func(t: float) -> void:
		# A parabola through start, the peak and the target.
		var y := lerpf(lerpf(start.y, peak, t), lerpf(peak, target.y, t), t)
		pet.position = Vector2(lerpf(start.x, target.x, t), y), 0.0, 1.0, duration)
	_tween.finished.connect(_land)


func exit() -> void:
	if _tween:
		_tween.kill()


func _land() -> void:
	if not is_active():
		return
	if pet.window_tracker.find_window(_window_id).is_empty():
		machine.transition_to(PetStateMachine.DRAGGED, {"falling": true})
	else:
		machine.transition_to(PetStateMachine.PERCHED, {"window_id": _window_id})
