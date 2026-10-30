extends Node
## Autoload `Unlocks`: which wardrobe items she can wear, from data/wardrobe/items.json.
## Items unlock locally (no store): by affection level, the best daily streak, Snack Time
## topics talked through, or an unlocked memory. Also keeps the daily streak: days in a
## row she's been run.

## A new item became available (once per item; she announces it).
signal item_unlocked(item: String, title: String)

const ITEMS_PATH := "res://data/wardrobe/items.json"

## category -> {"title", "none"}; item -> {"title", "rarity", "unlock"}.
var categories: Dictionary = {}
var items: Dictionary = {}


func _ready() -> void:
	var data: Variant = Dialogue.load_json(ITEMS_PATH)
	if data is Dictionary:
		categories = data.get("categories", {})
		items = data.get("items", {})
	update_streak()
	# Items already available when this runs for the first time don't need announcing.
	if SaveData.get_value(&"wardrobe/seen").is_empty():
		SaveData.set_value(&"wardrobe/seen", PackedStringArray(unlocked_items()))
	Affection.changed.connect(func(_points: int, _delta: int) -> void: check.call_deferred())
	SaveData.changed.connect(func(key: StringName) -> void:
		if key in [&"talk/memories", &"talk/unlocked_topics", &"stats/best_streak"]:
			check.call_deferred())


## Items in `category` ("hat", "glasses", ...) in data order, as "<category>/<item>".
func items_in(category: String) -> PackedStringArray:
	var found := PackedStringArray()
	for item: String in items:
		if item.begins_with(category + "/"):
			found.append(item)
	return found


func is_unlocked(item: String) -> bool:
	return missing(item).is_empty()


## What's still needed for `item`, in words ("" when it's unlocked).
func missing(item: String) -> String:
	if not items.has(item):
		return "unknown item"
	var unlock: Dictionary = items[item].get("unlock", {})
	var needs := PackedStringArray()
	if unlock.has("level") and Affection.get_level() < int(unlock.level):
		needs.append("affection level %d (%s)" % [unlock.level, Affection.LEVEL_NAMES[int(unlock.level)]])
	if unlock.has("streak") and SaveData.get_value(&"stats/best_streak") < int(unlock.streak):
		needs.append("a %d-day streak" % unlock.streak)
	if unlock.has("topics") and SaveData.get_value(&"talk/unlocked_topics").size() < int(unlock.topics):
		needs.append("%d Snack Time topics" % unlock.topics)
	if unlock.has("memory") and not SaveData.get_value(&"talk/memories").has(unlock.memory):
		needs.append(_memory_hint(unlock.memory))
	return ", ".join(needs)


func unlocked_items() -> PackedStringArray:
	var found := PackedStringArray()
	for item: String in items:
		if is_unlocked(item):
			found.append(item)
	return found


## Announces items that became available since the last check.
func check() -> void:
	var seen: PackedStringArray = SaveData.get_value(&"wardrobe/seen")
	var changed := false
	for item in unlocked_items():
		if not seen.has(item):
			seen.append(item)
			changed = true
			item_unlocked.emit(item, items[item].get("title", item))
	if changed:
		SaveData.set_value(&"wardrobe/seen", seen)


## Counts today towards the streak: days in a row, broken by a day without her.
func update_streak() -> void:
	var today := Time.get_date_string_from_system()
	var last: String = SaveData.get_value(&"stats/last_day")
	if last == today:
		return
	var yesterday := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400 + ReminderParser.system_bias())
	var streak: int = SaveData.get_value(&"stats/streak") + 1 if last == yesterday else 1
	SaveData.set_value(&"stats/last_day", today)
	SaveData.set_value(&"stats/streak", streak)
	if streak > SaveData.get_value(&"stats/best_streak"):
		SaveData.set_value(&"stats/best_streak", streak)


static func _memory_hint(memory: String) -> String:
	match memory:
		"first_sleep":
			return "letting her sleep once"
		_:
			return "a special moment"
