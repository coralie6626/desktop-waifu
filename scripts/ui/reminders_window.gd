class_name RemindersWindow
extends ToolWindow
## Keep time for me > All reminders...: every pending reminder, timer and alarm, soonest
## first, with how long until each. Pick one to change its text, time, repeat rule or
## countdown, or delete it; the box at the top adds a new one from plain text
## ("water the plants every day at 8").

const REPEATS: PackedStringArray = ["", ReminderParser.REPEAT_DAILY, ReminderParser.REPEAT_WEEKDAYS, ReminderParser.REPEAT_WEEKLY]
const REPEAT_NAMES: PackedStringArray = ["Once", "Every day", "Weekdays", "Every week"]

var _add := LineEdit.new()
var _list := ItemList.new()
var _text := LineEdit.new()
var _when := LineEdit.new()
var _repeat := OptionButton.new()
var _countdown := CheckBox.new()
var _status := ToolWindow.hint("")
## The reminder ids shown, one per list row.
var _ids := PackedStringArray()
var _selected := ""


func _ready() -> void:
	title = "Reminders"
	min_size = Vector2i(380, 420)
	size = Vector2i(420, 480)
	_add.placeholder_text = "Add... (e.g. water the plants every day at 8)"
	_add.text_submitted.connect(_on_add)
	content.add_child(_add)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	content.add_child(_list)

	var grid := GridContainer.new()
	grid.columns = 2
	content.add_child(grid)
	for row: Array in [["What", _text], ["When", _when], ["Repeat", _repeat]]:
		var label := Label.new()
		label.text = row[0]
		grid.add_child(label)
		row[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(row[1])
	_when.placeholder_text = "e.g. tomorrow 9am, friday 14:00, 01/12"
	for repeat_name in REPEAT_NAMES:
		_repeat.add_item(repeat_name)
	_countdown.text = "Count down the days (she'll mention it)"
	content.add_child(_countdown)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	for button: Array in [["Delete", _on_delete], ["Save changes", _on_save]]:
		var b := Button.new()
		b.text = button[0]
		b.pressed.connect(button[1])
		buttons.add_child(b)
	content.add_child(buttons)
	content.add_child(_status)
	Reminders.added.connect(_on_reminders_changed)
	Reminders.due.connect(_on_reminders_changed)


func open() -> void:
	_selected = ""
	_status.text = ""
	rebuild()
	open_centered()


func rebuild() -> void:
	_list.clear()
	_ids.clear()
	var now := int(Time.get_unix_time_from_system())
	for reminder: Dictionary in Reminders.list():
		_list.add_item(describe(reminder, now))
		_ids.append(reminder.id)
		if reminder.id == _selected:
			_list.select(_list.item_count - 1)
	if _list.item_count == 0:
		_list.add_item("Nothing yet. Type one above!", null, false)
		_list.set_item_disabled(0, true)
		_ids.append("")
	_fill_editor(_find(_selected))


## One list line: "call mom · tomorrow at 18:30 · every day · 3 days to go".
static func describe(reminder: Dictionary, now: int) -> String:
	var parts := PackedStringArray([reminder.text, ReminderParser.describe(int(reminder.due), now)])
	var repeat: String = reminder.get("repeat", "")
	if not repeat.is_empty():
		parts.append(REPEAT_NAMES[REPEATS.find(repeat)].to_lower())
	if reminder.get("countdown", false):
		parts.append(countdown_text(int(reminder.due), now))
	return " · ".join(parts)


## "3 days to go", "tomorrow!" or "today!", counting calendar days.
static func countdown_text(due: int, now: int) -> String:
	var bias := ReminderParser.system_bias()
	var days := floori((due + bias) / 86400.0) - floori((now + bias) / 86400.0)
	if days <= 0:
		return "today!"
	return "tomorrow!" if days == 1 else "%d days to go" % days


func _on_reminders_changed(_reminder: Dictionary) -> void:
	if visible:
		rebuild()


func _on_add(input: String) -> void:
	var reminder := Reminders.add_from_text(input)
	if reminder.is_empty():
		_status.text = "When? Add a time like \"at 6pm\", \"in 20 min\" or \"tomorrow 9am\"."
		return
	_add.clear()
	_selected = reminder.id
	_status.text = ""
	rebuild()


func _on_selected(index: int) -> void:
	_selected = _ids[index]
	_status.text = ""
	_fill_editor(_find(_selected))


func _fill_editor(reminder: Dictionary) -> void:
	_text.text = reminder.get("text", "")
	_when.text = ""
	_when.placeholder_text = ReminderParser.describe(int(reminder.due)) if not reminder.is_empty() else "e.g. tomorrow 9am, friday 14:00, 01/12"
	_repeat.select(maxi(0, REPEATS.find(reminder.get("repeat", ""))))
	_countdown.button_pressed = reminder.get("countdown", false)
	var editing := not reminder.is_empty()
	_text.editable = editing
	_when.editable = editing
	_repeat.disabled = not editing
	_countdown.disabled = not editing


func _on_save() -> void:
	if _selected.is_empty():
		return
	var changes := {
		"text": _text.text.strip_edges() if not _text.text.strip_edges().is_empty() else "Reminder",
		"repeat": REPEATS[_repeat.selected],
		"countdown": _countdown.button_pressed,
	}
	if not _when.text.strip_edges().is_empty():
		var parsed := ReminderParser.parse(_when.text)
		if parsed.is_empty():
			parsed = ReminderParser.parse("at " + _when.text)
		if parsed.is_empty():
			_status.text = "Couldn't read that time. Try \"tomorrow 9am\" or \"friday 14:00\"."
			return
		changes.due = parsed.due
	Reminders.update(_selected, changes)
	_status.text = "Saved."
	rebuild()


func _on_delete() -> void:
	if _selected.is_empty():
		return
	Reminders.remove(_selected)
	_selected = ""
	rebuild()


func _find(id: String) -> Dictionary:
	for reminder: Dictionary in Reminders.list():
		if reminder.id == id:
			return reminder
	return {}
