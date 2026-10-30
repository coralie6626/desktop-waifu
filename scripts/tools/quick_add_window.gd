class_name QuickAddWindow
extends ToolWindow
## A small box with one line of text: "Remind me...", a custom timer or an alarm.
## ask() shows it and returns what was typed, or "" if it was closed. A `validate`
## callable can reject the text with a message, keeping the box open.

signal _done(text: String)

var _prompt := Label.new()
var _field := LineEdit.new()
var _hint := ToolWindow.hint("")
var _validate := Callable()


func _ready() -> void:
	title = "Keep time"
	unresizable = true
	size = Vector2i(440, 120)
	content.add_child(_prompt)
	content.add_child(_field)
	content.add_child(_hint)
	_field.text_submitted.connect(_on_submitted)


## Shows the box in the middle of the screen and waits for an answer.
func ask(prompt: String, hint_text: String, validate := Callable()) -> String:
	_prompt.text = prompt
	_hint.text = hint_text
	_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	_validate = validate
	_field.clear()
	open_centered()
	_field.grab_focus()
	return await _done


func close() -> void:
	_finish("")


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
	_finish(text)


func _finish(text: String) -> void:
	hide()
	_done.emit(text)
