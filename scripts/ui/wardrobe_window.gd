class_name WardrobeWindow
extends ToolWindow
## Character > Wardrobe...: her outfit, pajamas, hat, glasses, bedding and cushion, with
## a live preview (a second SpineSprite). Locked items are listed with what unlocks them
## (see Unlocks); rare ones get a star. "Save" writes Settings wardrobe/*.

## The preview's pose for each category, so what you pick is visible.
const PREVIEW_ANIM := {"pajamas": &"idle", "bedding": &"sleep", "cushion": &"snack"}

var _preview := SpineSprite.new()
var _pickers: Dictionary[String, OptionButton] = {}
## category -> the item picked (without the category), "" for none.
var _values: Dictionary = {}


func _ready() -> void:
	title = "Wardrobe"
	unresizable = true
	size = Vector2i(520, 350)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	content.add_child(row)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(180, 240)
	stage.clip_contents = true
	row.add_child(stage)
	_preview.skeleton_data_res = preload("res://assets/characters/waifu/waifu_data.tres")
	_preview.position = Vector2(90, 228)
	stage.add_child(_preview)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grid)
	for category: String in Unlocks.categories:
		var label := Label.new()
		label.text = Unlocks.categories[category].get("title", category)
		grid.add_child(label)
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.fit_to_longest_item = false # Long locked names would widen the window.
		picker.clip_text = true
		picker.item_selected.connect(_on_picked.bind(category))
		grid.add_child(picker)
		_pickers[category] = picker
	content.add_child(ToolWindow.hint("Pajamas are worn in the evening and while she sleeps or watches games. Locked items show what unlocks them."))
	var save := Button.new()
	save.text = "Save"
	save.size_flags_horizontal = Control.SIZE_SHRINK_END
	save.pressed.connect(_save)
	content.add_child(save)


func open() -> void:
	if not visible:
		for category: String in _pickers:
			_values[category] = Wardrobe.chosen(category)
			_fill(category)
		_show(&"idle", false)
	open_centered()


func _fill(category: String) -> void:
	var picker := _pickers[category]
	picker.clear()
	if Unlocks.categories[category].get("none", false):
		picker.add_item("None")
		picker.set_item_metadata(0, "")
	for item in Unlocks.items_in(category):
		var info: Dictionary = Unlocks.items[item]
		var text: String = info.get("title", item)
		if info.get("rarity", "") == "rare":
			text += " ★"
		var missing := Unlocks.missing(item)
		if not missing.is_empty():
			text += " (locked)"
		picker.add_item(text)
		var index := picker.item_count - 1
		picker.set_item_metadata(index, item.get_slice("/", 1))
		if not missing.is_empty():
			picker.set_item_disabled(index, true)
			picker.set_item_tooltip(index, "Unlocks with " + missing)
	for i in picker.item_count:
		if picker.get_item_metadata(i) == _values[category]:
			picker.select(i)


func _on_picked(index: int, category: String) -> void:
	_values[category] = _pickers[category].get_item_metadata(index)
	_show(PREVIEW_ANIM.get(category, &"idle"), category in ["pajamas", "bedding"])


## Dresses the preview in the current picks and plays `anim`.
func _show(anim: StringName, pajamas: bool) -> void:
	Wardrobe.dress(_preview, Wardrobe.skin_names(pajamas, _values))
	_preview.get_animation_state().set_animation(anim, true, 0)
	# Lying poses are wider and lower: fit them in the stage.
	_preview.scale = Vector2(0.75, 0.75) if anim == &"sleep" else Vector2.ONE


func _save() -> void:
	for category: String in _values:
		Settings.set_value(StringName("wardrobe/" + category), _values[category])
	close()
