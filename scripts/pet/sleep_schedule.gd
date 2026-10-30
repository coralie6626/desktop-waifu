class_name SleepSchedule
extends Node
## Her bedtime routine, from Settings schedule/bedtime and schedule/wake_time ("HH:MM";
## an empty bedtime turns it off). Some hours before bedtime is WIND_DOWN: she changes
## into pajamas (see Wardrobe) and yawns (lines with "phase": "wind_down"). From bedtime
## to wake time is NIGHT: she asks to go to sleep, Yes or Stay up, and asks again a while
## after a "stay up"; kept up HARD_LIMIT_HOURS past bedtime, she dozes off without her
## blanket. Asleep, she's in the Sleeping state until wake time.

signal phase_changed(phase: Phase)

enum Phase { DAY, WIND_DOWN, NIGHT }

const PHASE_NAMES: PackedStringArray = ["day", "wind_down", "night"]
## Hours before bedtime that she starts winding down.
const WIND_DOWN_HOURS := 2.0
## Hours after bedtime that she can't stay awake any more and dozes off, blanket or not.
const HARD_LIMIT_HOURS := 2.0

## Minutes to wait before asking again after "stay up" (or a dismissed question).
@export var ask_again_minutes := 30.0
## How often the clock is checked, in seconds.
@export var check_interval := 10.0

var phase := Phase.DAY
## Ticks (msec) after which she may ask to go to sleep.
var _ask_after := 0
## Set when "Yes, good night" is picked, until the question's conversation ends.
var _wants_sleep := false

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	phase = current_phase()
	_pet.get_node(^"Conversation").action.connect(_on_action)
	var timer := Timer.new()
	timer.wait_time = check_interval
	timer.timeout.connect(check)
	add_child(timer)
	timer.start()


## Re-reads the clock: moves to a new phase, wakes her in the morning, and asks to go
## to sleep at night.
func check() -> void:
	var now_phase := current_phase()
	if now_phase != phase:
		phase = now_phase
		phase_changed.emit(phase)
		if phase == Phase.DAY:
			_ask_after = 0
			if _pet.state_machine.current_state.name == PetStateMachine.SLEEPING:
				_pet.state_machine.transition_to(PetStateMachine.IDLE)
				_pet.say_line(&"wake_up")
	if phase == Phase.NIGHT and _can_ask() and past_hard_limit():
		doze_off()
	elif phase == Phase.NIGHT and Time.get_ticks_msec() >= _ask_after and _can_ask():
		ask_to_sleep()


func ask_to_sleep() -> void:
	_ask_after = Time.get_ticks_msec() + int(ask_again_minutes * 60000.0)
	var finished := await _pet.conversation.run([{
		"line": "bedtime_ask",
		"choices": [
			{"text": "Yes, good night", "do": "go_to_sleep", "steps": [{"line": "bedtime_yes"}]},
			{"text": "Stay up a bit longer", "steps": [{"line": "bedtime_stay"}]},
		],
	}])
	if finished and _wants_sleep:
		_wants_sleep = false
		_pet.state_machine.transition_to(PetStateMachine.SLEEPING)


## Kept up too long, she falls asleep where she is, without her blanket (tuck her in!).
func doze_off() -> void:
	_pet.state_machine.transition_to(PetStateMachine.SLEEPING, {"blanket": false})
	_pet.say_line(&"dozed_off")


## Whether it's more than HARD_LIMIT_HOURS past bedtime (and still night).
static func past_hard_limit() -> bool:
	var bedtime := parse_clock(Settings.get_value(&"schedule/bedtime"))
	if bedtime < 0 or current_phase() != Phase.NIGHT:
		return false
	var clock := Time.get_time_dict_from_system()
	var since := posmod(clock.hour * 60 + clock.minute - bedtime, 1440)
	return since >= roundi(HARD_LIMIT_HOURS * 60.0)


## The phase for the current time and settings.
static func current_phase() -> Phase:
	var bedtime := parse_clock(Settings.get_value(&"schedule/bedtime"))
	var wake := parse_clock(Settings.get_value(&"schedule/wake_time"))
	if bedtime < 0 or wake < 0:
		return Phase.DAY
	var clock := Time.get_time_dict_from_system()
	return phase_at(clock.hour * 60 + clock.minute, bedtime, wake)


## The phase at `minute` (minutes since midnight) for a bedtime and wake time in minutes.
static func phase_at(minute: int, bedtime: int, wake: int) -> Phase:
	if _in_span(minute, bedtime, wake):
		return Phase.NIGHT
	var wind_down := posmod(bedtime - roundi(WIND_DOWN_HOURS * 60.0), 1440)
	if _in_span(minute, wind_down, bedtime):
		return Phase.WIND_DOWN
	return Phase.DAY


func _on_action(action: String, _value: Variant) -> void:
	if action == "go_to_sleep":
		_wants_sleep = true


## Only when she's free and somewhere she can lie down from.
func _can_ask() -> bool:
	if _pet.is_busy() or not _pet.visible:
		return false
	return _pet.state_machine.current_state.name in [PetStateMachine.IDLE, PetStateMachine.WANDER, PetStateMachine.SITTING]


## Whether `minute` is in [from, to) on a 24-hour clock that wraps at midnight.
static func _in_span(minute: int, from: int, to: int) -> bool:
	if from <= to:
		return minute >= from and minute < to
	return minute >= from or minute < to


## "HH:MM" as minutes since midnight, or -1 if empty or unreadable.
static func parse_clock(text: String) -> int:
	var parts := text.strip_edges().split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var hour := int(parts[0])
	var minute := int(parts[1])
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return -1
	return hour * 60 + minute
