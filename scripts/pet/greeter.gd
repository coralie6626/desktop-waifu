class_name Greeter
extends Node
## Hellos by time of day (Dialogue triggers greet_morning / greet_afternoon /
## greet_evening / greet_night, or missed_you after days away) shortly after she starts,
## with a word about the daily streak; a lunch nudge once a day; and "welcome back" when
## the PC wakes from sleep (the wall clock jumps ahead between two frames).

## Seconds after startup before she says hello.
@export var greet_delay := 1.5
## A jump of the wall clock this long between frames means the PC was asleep.
@export var away_minutes := 10.0
## Days away that count as "I missed you".
@export var missed_after_days := 2

var _last_wall := 0.0
var _lunch_day := ""

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	_last_wall = Time.get_unix_time_from_system()
	get_tree().create_timer(greet_delay).timeout.connect(greet)


## The hello for when she starts.
func greet() -> void:
	if not _pet.visible or _pet.is_busy():
		return
	if Affection.days_away >= missed_after_days:
		_pet.say_line(&"missed_you", -1.0, {"days": Affection.days_away})
		return
	var hour: int = Time.get_datetime_dict_from_system().hour
	var trigger := StringName("greet_" + Dialogue.time_of_day(hour))
	var streak: int = SaveData.get_value(&"stats/streak")
	if streak >= 2 and Dialogue.has_trigger(&"streak"):
		var hello := Dialogue.pick(trigger)
		var streak_line := Dialogue.pick(&"streak")
		_pet.say_message("%s %s" % [hello.get("text", ""), String(streak_line.get("text", "")).format({"days": streak})])
		_pet.play_reaction(hello.get("anim", &"happy"))
	else:
		_pet.say_line(trigger)


func _process(_delta: float) -> void:
	var wall := Time.get_unix_time_from_system()
	var jump := wall - _last_wall
	_last_wall = wall
	if jump > away_minutes * 60.0:
		_on_back_from_sleep()
	var now := Time.get_datetime_dict_from_system()
	var today := Time.get_date_string_from_system()
	if now.hour == 12 and now.minute < 30 and _lunch_day != today and not _pet.is_busy():
		_lunch_day = today
		_pet.say_line(&"lunch")


func _on_back_from_sleep() -> void:
	if _pet.visible and _pet.state_machine.current_state.name != PetStateMachine.SLEEPING:
		_pet.say_line(&"welcome_back_pc")
