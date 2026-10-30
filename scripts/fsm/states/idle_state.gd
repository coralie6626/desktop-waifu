extends PetState
## IDLE: stand on the taskbar. Every few seconds roll the dice:
## start wandering, say something, play a one-shot idle action, or now and then hop
## onto the title bar of the window in front.

@export var min_wait := 3.0
@export var max_wait := 7.0
@export_range(0.0, 1.0) var wander_chance := 0.5
## The remaining probability (1 - wander - talk) plays the "idle_action" animation.
@export_range(0.0, 1.0) var talk_chance := 0.25
## Chance per roll to hop onto the window in front instead (when it has a free spot).
@export_range(0.0, 1.0) var hop_chance := 0.08

var _wait := 0.0


func enter(_msg: Dictionary = {}) -> void:
	pet.play_anim(&"idle")
	_reset_timer()


func update(delta: float) -> void:
	if pet.is_busy():
		return # Hold still while being patted or talked to.
	_wait -= delta
	if _wait > 0.0:
		return

	_reset_timer()
	var roll := randf()
	if roll < hop_chance and _hop():
		return
	if roll < wander_chance:
		machine.transition_to(PetStateMachine.WANDER)
	elif roll < wander_chance + talk_chance:
		pet.say_line(&"idle")
	else:
		_play_idle_action()


## Hops onto the frontmost free title bar, if there is one. Returns whether she went.
func _hop() -> bool:
	var target := pet.window_tracker.find_hop_target(pet.position, pet.perch_top_range(), pet.perch_margin)
	if target.is_empty():
		return false
	machine.transition_to(PetStateMachine.HOP, {"window_id": target.id, "target": Vector2(target.x, target.rect.position.y)})
	return true


func _play_idle_action() -> void:
	if not pet.has_anim(&"idle_action"):
		pet.say_line(&"idle")
		return
	# "idle_action" must be listed in pet.one_shot_anims, otherwise animation_finished never fires.
	pet.play_anim(&"idle_action")
	await pet.animation_finished
	if is_active():
		pet.play_anim(&"idle")


func _reset_timer() -> void:
	_wait = randf_range(min_wait, max_wait)
