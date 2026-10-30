class_name TimeMenu
extends PopupMenu
## "Keep time for me": timers, alarms and reminders. Used as a submenu of the Talk menu
## and of the tray menu; each has its own instance, and both act through Reminders/Desk.

enum Id { TIMER_5, TIMER_15, FOCUS_25, CUSTOM_TIMER, ALARM, REMINDER, ALL, UPCOMING, CLEAR }

## Set by the owner: who answers "What's coming up?".
var pet: DesktopPet


func _ready() -> void:
	theme = preload("res://ui/menu_theme.tres")
	add_item("Timer: 5 minutes", Id.TIMER_5)
	add_item("Timer: 15 minutes", Id.TIMER_15)
	add_item("Focus timer: 25 minutes", Id.FOCUS_25)
	add_item("Custom timer...", Id.CUSTOM_TIMER)
	add_separator()
	add_item("Alarm...", Id.ALARM)
	add_item("Remind me...", Id.REMINDER)
	add_item("All reminders...", Id.ALL)
	add_separator()
	add_item("What's coming up?", Id.UPCOMING)
	add_item("Cancel all timers and reminders", Id.CLEAR)
	id_pressed.connect(_on_id_pressed)
	about_to_popup.connect(func() -> void: set_item_disabled(get_item_index(Id.CLEAR), Reminders.list().is_empty()))


func _on_id_pressed(id: int) -> void:
	match id:
		Id.TIMER_5:
			Reminders.add_timer(5 * 60)
		Id.TIMER_15:
			Reminders.add_timer(15 * 60)
		Id.FOCUS_25:
			Reminders.add_timer(25 * 60, "focus session")
		Id.CUSTOM_TIMER:
			Desk.ask_timer()
		Id.ALARM:
			Desk.ask_alarm()
		Id.REMINDER:
			Desk.ask_reminder()
		Id.ALL:
			Desk.open_reminders()
		Id.UPCOMING:
			if pet:
				pet.announcer.say_upcoming()
		Id.CLEAR:
			Reminders.clear()
			if pet:
				pet.say_line(&"reminders_cleared")
