extends Node
## Autoload `Desk`: owns the tool windows (Notes, Reminders, Schedule, Game whitelist,
## Wardrobe, Memories, and the one-line box used for custom timers, alarms and
## reminders) so the Talk menu and the tray share them. They're children of an autoload
## rather than of a menu, so they stay open after a menu closes.

var notes := NotesWindow.new()
var quick_add := QuickAddWindow.new()
var schedule := ScheduleWindow.new()
var games := GamesWindow.new()
var wardrobe := WardrobeWindow.new()
var memories := MemoriesWindow.new()
var reminders := RemindersWindow.new()


func _ready() -> void:
	add_child(notes)
	add_child(quick_add)
	add_child(schedule)
	add_child(games)
	add_child(wardrobe)
	add_child(memories)
	add_child(reminders)


func _exit_tree() -> void:
	notes.flush()


func open_schedule() -> void:
	schedule.open()


func open_games(last_app := "") -> void:
	games.open(last_app)


func open_wardrobe() -> void:
	wardrobe.open()


## `pet` replays the memory picked.
func open_memories(pet: DesktopPet) -> void:
	memories.pet = pet
	memories.open()


func open_reminders() -> void:
	reminders.open()


func open_notes() -> void:
	notes.open()


func ask_reminder() -> void:
	var input := await quick_add.ask("Remind me...", "e.g. \"call mom at 18:30\", \"stretch in 20 min\", \"dentist friday 14:00\"",
		func(text: String) -> String:
			return "" if not ReminderParser.parse(text).is_empty() else "When? Add a time like \"at 6pm\" or \"in 20 min\".")
	if not input.is_empty():
		Reminders.add_from_text(input)


func ask_timer() -> void:
	var input := await quick_add.ask("Timer: how long?", "e.g. \"10\" (minutes), \"1h 30m\", \"90 sec\"",
		func(text: String) -> String:
			return "" if ReminderParser.parse_duration(text) > 0 else "Try \"10\", \"10 min\" or \"1h 30m\".")
	if not input.is_empty():
		Reminders.add_timer(ReminderParser.parse_duration(input))


func ask_alarm() -> void:
	var input := await quick_add.ask("Alarm: what time?", "e.g. \"7:30\", \"6pm\", \"tomorrow 8am\"",
		func(text: String) -> String:
			return "" if not ReminderParser.parse("at " + text).is_empty() else "Try \"7:30\" or \"6pm\".")
	if not input.is_empty():
		var parsed := ReminderParser.parse("at " + input)
		Reminders.add("Alarm", parsed.due, Reminders.KIND_ALARM)
