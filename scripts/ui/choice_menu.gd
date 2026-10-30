class_name ChoiceMenu
extends PopupMenu
## The answer list for a question in a conversation, popped up beside her.
## Its own OS window (embed_subwindows is off), so it isn't clipped by the click region.

signal _answered(index: int)

var _choice := -1


func _ready() -> void:
	theme = preload("res://ui/menu_theme.tres")
	id_pressed.connect(func(id: int) -> void: _choice = id)
	# id_pressed comes before popup_hide; defer so the choice is already recorded.
	popup_hide.connect(func() -> void: _answered.emit.call_deferred(_choice))


## Shows `options` at `screen_position` and waits for one. Returns its index, or -1 if
## the menu was dismissed.
func ask(options: PackedStringArray, screen_position: Vector2i) -> int:
	clear()
	for i in options.size():
		add_item(options[i], i)
	_choice = -1
	popup(Rect2i(screen_position, Vector2i.ZERO))
	return await _answered
