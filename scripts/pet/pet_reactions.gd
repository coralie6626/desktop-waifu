class_name PetReactions
extends Node
## How she responds to touch: headpats, and a click on each part of her (see BodyParts).
## Poking her face, chest or skirt too often in a short time makes her annoyed for a
## while, and every click gets a pout until it wears off; a headpat makes up for it.
## What she says (and the expression with it) comes from Dialogue: the triggers are
## head, face, flustered, hands, annoyed, forgiven, pat, pat_end, first_pat, level_up,
## sleep_disturbed (a click while she sleeps) and woken_up (picked up while asleep).

@export_group("Headpats")
## Strokes (direction changes) per affection point.
@export var strokes_per_point := 6
## Strokes between happy lines while she's being patted.
@export var strokes_per_line := 10

@export_group("Annoyance")
## This many pokes (face, chest, skirt) within annoy_window seconds makes her annoyed.
@export var annoy_pokes := 4
@export var annoy_window := 10.0
@export var annoyed_time := 30.0
## Affection lost each time she gets annoyed.
@export var annoyed_penalty := 2

var _strokes := 0
var _poke_times: Array[float] = []
var _annoyed_until := 0.0

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	var gestures: PetGestures = _pet.get_node(^"Gestures")
	gestures.clicked.connect(_on_clicked)
	gestures.pat_started.connect(_on_pat_started)
	gestures.patted.connect(_on_patted)
	gestures.pat_ended.connect(_on_pat_ended)
	Affection.level_up.connect(_on_level_up)
	_pet.get_node(^"StateMachine").state_changed.connect(_on_state_changed)


func is_annoyed() -> bool:
	return _now() < _annoyed_until


func _on_clicked(position: Vector2) -> void:
	if _pet.announcer.is_active():
		_pet.bubble.hide_message() # Clicking her dismisses a reminder too.
		return
	if _pet.state_machine.current_state.name == PetStateMachine.SLEEPING:
		_pet.say_line(&"sleep_disturbed") # Only half wakes up.
		return
	if is_annoyed():
		_pet.say_line(&"annoyed")
		return
	match _pet.get_body_part(position):
		&"head":
			_pet.say_line(&"head")
		&"hands":
			_pet.say_line(&"hands")
			Affection.add(1)
		&"face":
			if not _poke():
				_pet.say_line(&"face")
		&"chest", &"skirt":
			if not _poke():
				_pet.say_line(&"flustered")
		_:
			_pet.say_line(&"idle")


## Counts a poke. Returns true if it was the last straw (she's now annoyed and has
## already reacted).
func _poke() -> bool:
	var now := _now()
	_poke_times.append(now)
	while _poke_times[0] < now - annoy_window:
		_poke_times.pop_front()
	if _poke_times.size() < annoy_pokes:
		return false
	_poke_times.clear()
	_annoyed_until = now + annoyed_time
	Affection.add(-annoyed_penalty)
	_pet.say_line(&"annoyed")
	return true


func _on_pat_started() -> void:
	_strokes = 0
	# She stops to enjoy it instead of walking off from under the cursor.
	if _pet.state_machine.current_state.name == PetStateMachine.WANDER:
		_pet.state_machine.transition_to(PetStateMachine.IDLE)
	if is_annoyed():
		_annoyed_until = 0.0
		_poke_times.clear()
		_pet.say_line(&"forgiven")
	elif SaveData.unlock_memory("first_headpat"):
		_pet.say_line(&"first_pat")
	# After the line, whose own reaction would otherwise replace the pat loop.
	_pet.play_reaction(&"pat", true)


func _on_patted() -> void:
	_strokes += 1
	if _strokes % strokes_per_point == 0:
		Affection.add(1)
	if _strokes % strokes_per_line == 0:
		_pet.say_line(&"pat")


func _on_pat_ended() -> void:
	_pet.stop_reaction()
	if _strokes >= strokes_per_point:
		_pet.say_line(&"pat_end")


func _on_level_up(_level: int) -> void:
	_pet.say_line(&"level_up", 5.0)


func _on_state_changed(from: StringName, to: StringName) -> void:
	if from == PetStateMachine.SLEEPING and to == PetStateMachine.DRAGGED:
		_pet.say_line(&"woken_up")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
