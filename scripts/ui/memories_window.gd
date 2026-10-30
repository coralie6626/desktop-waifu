class_name MemoriesWindow
extends ToolWindow
## Talk > Memories...: what she remembers with you: milestones (data/talk/memories.json,
## unlocked through SaveData.unlock_memory) and the Snack Time topics you've talked
## through. Double-click one, or pick it and press Replay, to hear it again.

const MEMORIES_PATH := "res://data/talk/memories.json"

## Who replays them. Set by whoever opens the window.
var pet: DesktopPet

var _list := ItemList.new()
var _count := ToolWindow.hint("")
## One per list row: the steps to replay, or [] for a heading.
var _entries: Array = []


func _ready() -> void:
	title = "Memories"
	min_size = Vector2i(300, 300)
	size = Vector2i(360, 400)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_replay)
	content.add_child(_list)
	content.add_child(_count)
	var replay := Button.new()
	replay.text = "Replay"
	replay.size_flags_horizontal = Control.SIZE_SHRINK_END
	replay.pressed.connect(func() -> void:
		var selected := _list.get_selected_items()
		if not selected.is_empty():
			_replay(selected[0]))
	content.add_child(replay)


func open() -> void:
	rebuild()
	open_centered()


## Every milestone definition, as in the data file.
static func all_memories() -> Array:
	var data: Variant = Dialogue.load_json(MEMORIES_PATH)
	return data.get("memories", []) if data is Dictionary else []


func rebuild() -> void:
	_list.clear()
	_entries.clear()
	var unlocked: Dictionary = SaveData.get_value(&"talk/memories")
	var milestones := all_memories()
	var found := 0
	_heading("Milestones")
	for memory: Dictionary in milestones:
		if unlocked.has(memory.id):
			_add(memory.title, memory.steps)
			found += 1
	var topics: PackedStringArray = SaveData.get_value(&"talk/unlocked_topics")
	_heading("Snack Time")
	for id in topics:
		var topic := SnackTime.find_topic(id)
		if not topic.is_empty():
			_add(topic.title, topic.steps)
	var hidden := milestones.size() - found + SnackTime.all_topics().size() - topics.size()
	_count.text = "%d more to discover." % hidden if hidden > 0 else "You've found them all!"


func _heading(text: String) -> void:
	_list.add_item(text, null, false)
	_list.set_item_disabled(_list.item_count - 1, true)
	_entries.append([])


func _add(text: String, steps: Array) -> void:
	_list.add_item("   " + text)
	_entries.append(steps)


func _replay(index: int) -> void:
	var steps: Array = _entries[index]
	if steps.is_empty() or pet == null:
		return
	close()
	pet.conversation.run(steps)
