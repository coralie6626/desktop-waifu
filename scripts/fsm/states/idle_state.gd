extends PetState
## IDLE: stand on the taskbar. Every few seconds roll the dice:
## start wandering, say something, or play a one-shot idle action.

@export var min_wait := 3.0
@export var max_wait := 7.0
@export_range(0.0, 1.0) var wander_chance := 0.5
## The remaining probability (1 - wander - talk) plays the "idle_action" animation.
@export_range(0.0, 1.0) var talk_chance := 0.25

var _wait := 0.0


func enter(_msg: Dictionary = {}) -> void:
	pet.play_anim(&"idle")
	_reset_timer()


func update(delta: float) -> void:
	if pet.gestures.is_patting():
		return # Hold still while being patted.
	_wait -= delta
	if _wait > 0.0:
		return

	_reset_timer()
	var roll := randf()
	if roll < wander_chance:
		machine.transition_to(PetStateMachine.WANDER)
	elif roll < wander_chance + talk_chance:
		pet.say_random_line()
	else:
		_play_idle_action()


func _play_idle_action() -> void:
	if not pet.has_anim(&"idle_action"):
		pet.say_random_line()
		return
	# "idle_action" must be listed in pet.one_shot_anims, otherwise animation_finished never fires.
	pet.play_anim(&"idle_action")
	await pet.animation_finished
	if is_active():
		pet.play_anim(&"idle")


func _reset_timer() -> void:
	_wait = randf_range(min_wait, max_wait)
