class_name NotesWindow
extends Window
## The scratchpad: a small always-on-top window with a text area, saved to
## user://notes.txt as you type. The box underneath turns a line like
## "call mom at 18:30" into a reminder.

const PATH := "user://notes.txt"
## Seconds after the last keystroke before the notes are saved.
const SAVE_DELAY := 0.8

var _text := TextEdit.new()
var _quick_add := LineEdit.new()
var _status := Label.new()
var _save_timer := Timer.new()


func _ready() -> void:
	title = "Notes"
	always_on_top = true
	transient = false
	wrap_controls = true
	min_size = Vector2i(260, 200)
	size = Vector2i(340, 320)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)

	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.placeholder_text = "Jot something down..."
	_text.text_changed.connect(_save_timer.start)
	box.add_child(_text)

	_quick_add.placeholder_text = "Remind me... (e.g. call mom at 18:30)"
	_quick_add.text_submitted.connect(_on_quick_add)
	box.add_child(_quick_add)
	_status.add_theme_font_size_override(&"font_size", 12)
	box.add_child(_status)

	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	close_requested.connect(close)
	hide()


func open() -> void:
	if visible:
		grab_focus()
		return
	_text.text = load_notes()
	_status.text = ""
	show()
	move_to_center() # Not popup_centered(): that makes it transient, which on-top windows can't be.
	_text.grab_focus()


func close() -> void:
	save()
	hide()


## Writes the notes now (they also save themselves shortly after each change).
func save() -> void:
	_save_timer.stop()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("Notes: couldn't save %s (%s)" % [PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(_text.text)


static func load_notes() -> String:
	return FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""


## Saves unsaved typing, e.g. when the app quits with the window open.
func flush() -> void:
	if not _save_timer.is_stopped():
		save()


func _on_quick_add(input: String) -> void:
	if input.strip_edges().is_empty():
		return
	var reminder := Reminders.add_from_text(input)
	if reminder.is_empty():
		_status.text = "When? Add a time like \"at 6pm\", \"in 20 min\" or \"tomorrow 9am\"."
		return
	_status.text = "Reminder set %s: %s" % [ReminderParser.describe(reminder.due), reminder.text]
	_quick_add.clear()
