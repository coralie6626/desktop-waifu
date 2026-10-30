class_name QuickAddWindow
extends Window
## A small always-on-top box with one line of text: "Remind me...", a custom timer or an
## alarm. ask() shows it and returns what was typed, or "" if it was closed. A
## `validate` callable can reject the text with a message, keeping the box open.

signal _done(text: String)

var _prompt := Label.new()
var _field := LineEdit.new()
var _hint := Label.new()
var _validate := Callable()


func _ready() -> void:
	title = "Keep time"
	always_on_top = true
	transient = false
	unresizable = true
	wrap_controls = true
	size = Vector2i(440, 120)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	box.add_child(_prompt)
	box.add_child(_field)
	_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	_hint.add_theme_font_size_override(&"font_size", 12)
	box.add_child(_hint)
	_field.text_submitted.connect(_on_submitted)
	close_requested.connect(_close.bind(""))
	window_input.connect(_on_window_input)
	hide()


## Shows the box in the middle of the screen and waits for an answer.
func ask(prompt: String, hint: String, validate := Callable()) -> String:
	_prompt.text = prompt
	_hint.text = hint
	_hint.remove_theme_color_override(&"font_color")
	_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	_validate = validate
	_field.clear()
	show()
	move_to_center() # Not popup_centered(): that makes it transient, which on-top windows can't be.
	_field.grab_focus()
	return await _done


func _on_submitted(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	if _validate.is_valid():
		var problem: String = _validate.call(text)
		if not problem.is_empty():
			_hint.text = problem
			_hint.add_theme_color_override(&"font_color", Color(1, 0.6, 0.55))
			return
	_close(text)


func _on_window_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_close("")


func _close(text: String) -> void:
	hide()
	_done.emit(text)
