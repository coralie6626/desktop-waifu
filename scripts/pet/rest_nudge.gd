class_name RestNudge
extends Node
## Every so often (Settings schedule/rest_reminder_minutes; 0 turns it off) she reminds
## you to stand up, stretch or drink some water (Dialogue trigger "rest"). The count
## pauses while she's hidden and starts over while she sleeps or watches a game.

## States in which time doesn't count towards the next nudge.
const PAUSED_STATES: Array[StringName] = [PetStateMachine.SLEEPING, PetStateMachine.WATCHING]

## Seconds counted since the last nudge.
var elapsed := 0.0

@onready var _pet := get_parent() as DesktopPet


func _process(delta: float) -> void:
	var minutes: int = Settings.get_value(&"schedule/rest_reminder_minutes")
	var state := _pet.state_machine.current_state
	if minutes <= 0 or state == null or PAUSED_STATES.has(state.name):
		elapsed = 0.0
		return
	elapsed += delta
	if elapsed >= minutes * 60.0 and not _pet.is_busy():
		elapsed = 0.0
		_pet.say_line(&"rest", 6.0)
