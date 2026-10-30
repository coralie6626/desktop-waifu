class_name ScheduleWindow
extends ToolWindow
## Character > Schedule...: her bedtime and wake time (see SleepSchedule) and how often
## she nudges you to take a break (see RestNudge). Saved to Settings on "Save".

var _bedtime := LineEdit.new()
var _wake := LineEdit.new()
var _rest := SpinBox.new()
var _status := ToolWindow.hint("")


func _ready() -> void:
	title = "Schedule"
	unresizable = true
	size = Vector2i(360, 250)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 12)
	content.add_child(grid)
	_row(grid, "Bedtime", _bedtime, "23:00 (empty = no bedtime)")
	_row(grid, "Wake up at", _wake, "07:00")
	_rest.min_value = 0
	_rest.max_value = 240
	_rest.step = 5
	_rest.suffix = "min"
	_row(grid, "Break reminder every", _rest, "")
	content.add_child(ToolWindow.hint("She changes into pajamas two hours before bedtime. A break reminder of 0 turns them off."))
	var save := Button.new()
	save.text = "Save"
	save.size_flags_horizontal = Control.SIZE_SHRINK_END
	save.pressed.connect(_save)
	content.add_child(save)
	content.add_child(_status)


func open() -> void:
	if not visible:
		_bedtime.text = Settings.get_value(&"schedule/bedtime")
		_wake.text = Settings.get_value(&"schedule/wake_time")
		_rest.value = Settings.get_value(&"schedule/rest_reminder_minutes")
		_status.text = ""
	open_centered()


func _save() -> void:
	var bedtime := _bedtime.text.strip_edges()
	var wake := _wake.text.strip_edges()
	if not bedtime.is_empty() and SleepSchedule.parse_clock(bedtime) < 0:
		_status.text = "Bedtime should look like 23:00."
		return
	if SleepSchedule.parse_clock(wake) < 0:
		_status.text = "Wake-up time should look like 07:00."
		return
	Settings.set_value(&"schedule/bedtime", bedtime)
	Settings.set_value(&"schedule/wake_time", wake)
	Settings.set_value(&"schedule/rest_reminder_minutes", int(_rest.value))
	close()


static func _row(grid: GridContainer, label_text: String, field: Control, placeholder: String) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if field is LineEdit:
		field.placeholder_text = placeholder
	grid.add_child(field)
