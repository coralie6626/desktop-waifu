class_name GameWatcher
extends Node
## Notices when a game or full-screen app is in front, from WindowTracker's foreground
## window, and sends her to the Watching state until it's gone. Settings games/whitelist
## lists executables that always count, even windowed; games/blacklist lists ones that
## never do (say, a video player you don't want her to react to). Names are matched
## without case, with or without ".exe".

## States she can be called away from to watch.
const CAN_WATCH_FROM: Array[StringName] = [PetStateMachine.IDLE, PetStateMachine.WANDER, PetStateMachine.SITTING]

## Seconds between foreground checks.
@export var poll_interval := 2.0

var game_in_front := false

var _poll := Timer.new()

@onready var _pet := get_parent() as DesktopPet
@onready var _tracker: WindowTracker = $"../WindowTracker"


func _ready() -> void:
	_poll.wait_time = poll_interval
	_poll.timeout.connect(_tracker.request_update)
	add_child(_poll)
	_poll.start()
	_tracker.updated.connect(evaluate)


## Whether `foreground` ({"exe", "fullscreen"}, or {}) counts as a game.
static func is_game(foreground: Dictionary, whitelist: PackedStringArray, blacklist: PackedStringArray) -> bool:
	if foreground.is_empty():
		return false
	var exe := _normalise(foreground.get("exe", ""))
	for entry in blacklist:
		if _normalise(entry) == exe:
			return false
	for entry in whitelist:
		if _normalise(entry) == exe:
			return true
	return foreground.get("fullscreen", false)


## Re-checks the foreground window and moves her in or out of Watching.
func evaluate() -> void:
	game_in_front = is_game(_tracker.foreground, Settings.get_value(&"games/whitelist"), Settings.get_value(&"games/blacklist"))
	var machine := _pet.state_machine
	if machine.current_state == null:
		return # Not started yet.
	var state := machine.current_state.name
	if game_in_front and state in CAN_WATCH_FROM and not _pet.is_busy():
		machine.transition_to(PetStateMachine.WATCHING)
	elif not game_in_front and state == PetStateMachine.WATCHING:
		machine.transition_to(PetStateMachine.IDLE)


static func _normalise(exe: String) -> String:
	return exe.strip_edges().to_lower().trim_suffix(".exe")
