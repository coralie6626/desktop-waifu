class_name PetAnnouncer
extends Node
## Tells you when a reminder, timer or alarm comes due (see Reminders): she shows herself
## if hidden, walks to the middle of the taskbar (the Announce state), waves and keeps
## the message up until it's clicked. Several due at once come one after another.
## Also confirms new reminders and answers "What's coming up?".
## Lines come from Dialogue: reminder_set, timer_set, alarm_set, reminder_due,
## timer_done, alarm_due, upcoming_none, with {text}, {when} and {time} filled in.

## Shown this many seconds after it was due, she says when that was.
@export var late_after := 120
## How many upcoming reminders "What's coming up?" lists.
@export var upcoming_count := 3

var _queue: Array[Dictionary] = []
var _active := false

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	Reminders.due.connect(_on_due)
	Reminders.added.connect(_on_added)


## True from when she starts heading out to announce until the message is dismissed.
func is_active() -> bool:
	return _active


func _process(_delta: float) -> void:
	if _active or _queue.is_empty() or _pet.is_busy():
		return
	match _pet.state_machine.current_state.name:
		PetStateMachine.IDLE, PetStateMachine.WANDER, PetStateMachine.SITTING:
			_active = true
			_pet.state_machine.transition_to(PetStateMachine.ANNOUNCE)
		PetStateMachine.PERCHED:
			_active = true
			show_next() # Announce from the title bar.
		_:
			pass # Being carried or falling: wait until she lands.


## Shows the next due message; the Announce state calls it once she's in place.
func show_next() -> void:
	if _queue.is_empty():
		_active = false
		return
	var reminder: Dictionary = _queue.pop_front()
	_pet.play_reaction(&"idle_action")
	_pet.say_message(message_for(reminder), 3600.0)
	await _pet.bubble.closed
	_active = false
	if _pet.state_machine.current_state.name == PetStateMachine.ANNOUNCE:
		_pet.state_machine.transition_to(PetStateMachine.IDLE)


## Called if she's picked up on the way: the message waits for the next chance.
func abort() -> void:
	_active = false


func message_for(reminder: Dictionary, now: int = -1) -> String:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var trigger: StringName = {
		Reminders.KIND_TIMER: &"timer_done",
		Reminders.KIND_ALARM: &"alarm_due",
	}.get(reminder.kind, &"reminder_due")
	var clock := _clock(reminder.due)
	var line := Dialogue.pick(trigger)
	var text: String = line.text if not line.is_empty() else "Reminder: {text}"
	text = text.format({"text": reminder.text, "time": clock})
	if now - int(reminder.due) > late_after:
		text += "\n(It was due at %s.)" % clock
	return text


func say_upcoming() -> void:
	var pending := Reminders.list()
	if pending.is_empty():
		_pet.say_line(&"upcoming_none")
		return
	var lines := PackedStringArray(["Coming up:"])
	for reminder: Dictionary in pending.slice(0, upcoming_count):
		lines.append("• %s %s" % [reminder.text, ReminderParser.describe(reminder.due)])
	if pending.size() > upcoming_count:
		lines.append("...and %d more." % (pending.size() - upcoming_count))
	_pet.say_message("\n".join(lines), 6.0)


func _on_due(reminder: Dictionary) -> void:
	_queue.append(reminder)
	if not _pet.visible:
		_pet.set_shown(true)


func _on_added(reminder: Dictionary) -> void:
	var trigger: StringName = {
		Reminders.KIND_TIMER: &"timer_set",
		Reminders.KIND_ALARM: &"alarm_set",
	}.get(reminder.kind, &"reminder_set")
	_pet.say_line(trigger, -1.0, {"text": reminder.text, "when": ReminderParser.describe(reminder.due)})


static func _clock(unix: int) -> String:
	var local := Time.get_datetime_dict_from_unix_time(unix + ReminderParser.system_bias())
	return "%d:%02d" % [local.hour, local.minute]
