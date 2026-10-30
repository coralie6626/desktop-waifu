class_name ToolWindow
extends Window
## Base for her small always-on-top tool windows (Notes, the quick-add box, Schedule,
## Game whitelist): a padded column of controls, hidden until opened, closed by the
## title bar's X or Escape.

## The column subclasses add their controls to.
var content := VBoxContainer.new()


func _init() -> void:
	always_on_top = true
	transient = false
	wrap_controls = true
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	margin.add_child(content)
	close_requested.connect(close)
	window_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_cancel"):
			close())


## Shows the window in the middle of the screen, or brings it forward if it's open.
func open_centered() -> void:
	if visible:
		grab_focus()
		return
	show()
	move_to_center() # Not popup_centered(): that makes it transient, which on-top windows can't be.


## Override to save or report before hiding.
func close() -> void:
	hide()


## A small grey hint line.
static func hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	return label
