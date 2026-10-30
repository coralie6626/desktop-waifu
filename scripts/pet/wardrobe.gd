class_name Wardrobe
extends Node
## Dresses her by combining Spine skins at runtime: an outfit, a hat, glasses and bedding,
## chosen in Settings (wardrobe/*). The body and the default dress live in the skeleton's
## default skin, which every skin falls back to.
## Pajamas (by default with the nightcap) replace the outfit in the evening and at night
## (see SleepSchedule), and while she's asleep or watching a game.
## Skins are named "<category>/<item>" in waifu.spine-json; an item without a skin there
## (like the default dress) simply adds nothing.

## States in which she's always in pajamas.
const PAJAMA_STATES: Array[StringName] = [PetStateMachine.SLEEPING, PetStateMachine.WATCHING]

## The skins currently worn, for anyone who wants to know (e.g. tests, the wardrobe UI).
var worn := PackedStringArray()

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	Settings.changed.connect(func(key: StringName) -> void:
		if String(key).begins_with("wardrobe/"):
			refresh())
	_pet.get_node(^"StateMachine").state_changed.connect(func(_from: StringName, _to: StringName) -> void: refresh())
	_pet.get_node(^"SleepSchedule").phase_changed.connect(func(_phase: int) -> void: refresh())
	refresh.call_deferred()


func wants_pajamas() -> bool:
	var state := _pet.state_machine.current_state
	if state and PAJAMA_STATES.has(state.name):
		return true
	return _pet.sleep_schedule.phase != SleepSchedule.Phase.DAY


## The skins she should be wearing right now.
func skin_names(pajamas: bool) -> PackedStringArray:
	var names := PackedStringArray()
	var hat: String = Settings.get_value(&"wardrobe/hat")
	if pajamas:
		var set_name: String = Settings.get_value(&"wardrobe/pajamas")
		names.append("outfit/" + ("pajamas" if set_name == "default" else set_name))
		if hat.is_empty() and set_name == "default":
			hat = "nightcap"
	else:
		names.append("outfit/" + Settings.get_value(&"wardrobe/outfit"))
	if not hat.is_empty():
		names.append("hat/" + hat)
	var glasses: String = Settings.get_value(&"wardrobe/glasses")
	if not glasses.is_empty():
		names.append("glasses/" + glasses)
	names.append("bedding/" + Settings.get_value(&"wardrobe/bedding"))
	names.append("cushion/" + Settings.get_value(&"wardrobe/cushion"))
	return names


## Re-dresses her if what she should wear has changed.
func refresh() -> void:
	var data := _pet.sprite.skeleton_data_res
	var names := PackedStringArray()
	for skin_name in skin_names(wants_pajamas()):
		if data.find_skin(skin_name) != null:
			names.append(skin_name)
	if names == worn:
		return
	worn = names
	var skin := _pet.sprite.new_skin("worn")
	for skin_name in names:
		skin.add_skin(data.find_skin(skin_name))
	var skeleton := _pet.sprite.get_skeleton()
	skeleton.set_skin(skin)
	# Re-attach everything for the new skin; the animations then key over it as usual.
	skeleton.set_slots_to_setup_pose()
	_pet.sprite.get_animation_state().apply(skeleton)
