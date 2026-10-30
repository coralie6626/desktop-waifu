class_name Wardrobe
extends Node
## Dresses her by combining Spine skins at runtime: an outfit, a hat, glasses and bedding,
## chosen in Settings (wardrobe/*). The body and the default dress live in the skeleton's
## default skin, which every skin falls back to.
## Pajamas (by default with the nightcap) replace the outfit in the evening and at night
## (see SleepSchedule), and while she's asleep or watching a game.
## Items are "<category>/<item>" (see data/wardrobe/items.json and Unlocks); a chosen
## item that isn't unlocked yet falls back to the default. Skins in waifu.spine-json use
## the same names; an item without a skin there (like the default dress) adds nothing.

## States in which she's always in pajamas.
const PAJAMA_STATES: Array[StringName] = [PetStateMachine.SLEEPING, PetStateMachine.WATCHING]
## Categories that may be left empty ("none").
const OPTIONAL: PackedStringArray = ["hat", "glasses"]

## The skins currently worn, for anyone who wants to know (e.g. tests, the wardrobe UI).
var worn := PackedStringArray()

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	Settings.changed.connect(func(key: StringName) -> void:
		if String(key).begins_with("wardrobe/"):
			refresh())
	Unlocks.item_unlocked.connect(_on_item_unlocked)
	_pet.get_node(^"StateMachine").state_changed.connect(func(_from: StringName, _to: StringName) -> void: refresh())
	_pet.get_node(^"SleepSchedule").phase_changed.connect(func(_phase: int) -> void: refresh())
	refresh.call_deferred()


func wants_pajamas() -> bool:
	var state := _pet.state_machine.current_state
	if state and PAJAMA_STATES.has(state.name):
		return true
	return _pet.sleep_schedule.phase != SleepSchedule.Phase.DAY


## The skins for the chosen wardrobe, in pajamas or not. `choice` overrides Settings per
## category (the wardrobe window's preview uses it).
static func skin_names(pajamas: bool, choice: Dictionary = {}) -> PackedStringArray:
	var names := PackedStringArray()
	var hat := chosen("hat", choice)
	if pajamas:
		var set_name := chosen("pajamas", choice)
		names.append_array(skins_for("pajamas/" + set_name))
		if hat.is_empty() and set_name == "default":
			hat = "nightcap"
	else:
		names.append_array(skins_for("outfit/" + chosen("outfit", choice)))
	if not hat.is_empty():
		names.append("hat/" + hat)
	var glasses := chosen("glasses", choice)
	if not glasses.is_empty():
		names.append("glasses/" + glasses)
	names.append("bedding/" + chosen("bedding", choice))
	names.append("cushion/" + chosen("cushion", choice))
	return names


## The item chosen in `category`, or its default if that isn't unlocked.
static func chosen(category: String, choice: Dictionary = {}) -> String:
	var value: String = choice.get(category, Settings.get_value(StringName("wardrobe/" + category)))
	if value.is_empty() and OPTIONAL.has(category):
		return ""
	if value.is_empty() or not Unlocks.is_unlocked(category + "/" + value):
		return "" if OPTIONAL.has(category) else "default"
	return value


## The skins an item is made of (the pajama set reuses the outfit skin).
static func skins_for(item: String) -> PackedStringArray:
	if item == "pajamas/default":
		return PackedStringArray(["outfit/pajamas"])
	return PackedStringArray([item])


## Dresses `sprite` in the skins named (those it doesn't have are skipped). Returns the
## skins actually worn.
static func dress(sprite: SpineSprite, names: PackedStringArray) -> PackedStringArray:
	var data := sprite.skeleton_data_res
	var worn_now := PackedStringArray()
	var skin := sprite.new_skin("worn")
	for skin_name in names:
		var part := data.find_skin(skin_name)
		if part != null:
			skin.add_skin(part)
			worn_now.append(skin_name)
	var skeleton := sprite.get_skeleton()
	skeleton.set_skin(skin)
	# Re-attach everything for the new skin; the animations then key over it as usual.
	skeleton.set_slots_to_setup_pose()
	sprite.get_animation_state().apply(skeleton)
	return worn_now


## Re-dresses her if what she should wear has changed.
func refresh() -> void:
	var data := _pet.sprite.skeleton_data_res
	var names := PackedStringArray()
	for skin_name in skin_names(wants_pajamas()):
		if data.find_skin(skin_name) != null:
			names.append(skin_name)
	if names != worn:
		worn = dress(_pet.sprite, names)


func _on_item_unlocked(_item: String, title: String) -> void:
	_pet.say_line(&"new_item", 5.0, {"item": title})
	refresh()
