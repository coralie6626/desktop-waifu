class_name GamesWindow
extends ToolWindow
## Settings > Game whitelist...: executables that always count as a game, even
## windowed, and ones that never do (see GameWatcher). One name per line; the app you
## were last using can be added with one click.

var _whitelist := TextEdit.new()
var _blacklist := TextEdit.new()
var _last_app := ""
var _last_label := Label.new()
var _add_white := Button.new()
var _add_black := Button.new()


func _ready() -> void:
	title = "Game whitelist"
	min_size = Vector2i(360, 320)
	size = Vector2i(400, 380)
	content.add_child(ToolWindow.hint("Full-screen apps count as games. List names like game.exe, one per line."))
	content.add_child(_label("Always a game (even windowed):"))
	content.add_child(_list(_whitelist))
	content.add_child(_label("Never a game:"))
	content.add_child(_list(_blacklist))
	var row := HBoxContainer.new()
	row.add_child(_last_label)
	_last_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_last_label.clip_text = true
	_add_white.text = "Always"
	_add_white.pressed.connect(func() -> void: _append(_whitelist, _last_app))
	_add_black.text = "Never"
	_add_black.pressed.connect(func() -> void: _append(_blacklist, _last_app))
	row.add_child(_add_white)
	row.add_child(_add_black)
	content.add_child(row)
	var save := Button.new()
	save.text = "Save"
	save.size_flags_horizontal = Control.SIZE_SHRINK_END
	save.pressed.connect(_save)
	content.add_child(save)


## Opens the window; `last_app` (e.g. "game.exe") is offered for one-click adding.
func open(last_app := "") -> void:
	_last_app = last_app
	_last_label.text = "Last app: %s" % last_app if not last_app.is_empty() else "Last app: (none yet)"
	_add_white.disabled = last_app.is_empty()
	_add_black.disabled = last_app.is_empty()
	if not visible:
		_whitelist.text = "\n".join(Settings.get_value(&"games/whitelist"))
		_blacklist.text = "\n".join(Settings.get_value(&"games/blacklist"))
	open_centered()


func _save() -> void:
	Settings.set_value(&"games/whitelist", _names(_whitelist.text))
	Settings.set_value(&"games/blacklist", _names(_blacklist.text))
	close()


## The non-empty, trimmed lines of `text`.
static func _names(text: String) -> PackedStringArray:
	var names := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().is_empty():
			names.append(line.strip_edges())
	return names


static func _append(list: TextEdit, exe: String) -> void:
	if exe.is_empty() or _names(list.text).has(exe):
		return
	list.text = (list.text.strip_edges() + "\n" + exe).strip_edges()


static func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


static func _list(edit: TextEdit) -> TextEdit:
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = "game.exe"
	return edit
