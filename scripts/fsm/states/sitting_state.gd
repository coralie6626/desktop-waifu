extends PetState
## SITTING: anchored to the top edge of the taskbar (pet.floor_y). Stands up after a while.

@export var min_sit_time := 8.0
@export var max_sit_time := 20.0
@export_range(0.0, 1.0) var talk_chance := 0.5

var _time_left := 0.0


func enter(_msg: Dictionary = {}) -> void:
	pet.position.y = pet.floor_y
	pet.play_anim(&"sit")
	_time_left = randf_range(min_sit_time, max_sit_time)
	if randf() < talk_chance:
		pet.say_line(&"sit")


func update(delta: float) -> void:
	if pet.is_busy():
		return # Stay seated while being patted or talked to.
	_time_left -= delta
	if _time_left <= 0.0:
		machine.transition_to(PetStateMachine.IDLE)
