class_name PetState
extends Node
## Base class for every pet state. Each state is a child node of PetStateMachine;
## the node's name is the state's id (see the constants in PetStateMachine).
## Override only the hooks you need.

## Injected by PetStateMachine.start().
var pet: DesktopPet
var machine: PetStateMachine


## Called when the state becomes active. `msg` carries optional data from the previous state.
func enter(_msg: Dictionary = {}) -> void:
	pass


## Called right before the machine switches to another state.
func exit() -> void:
	pass


## Called every frame while this state is active.
func update(_delta: float) -> void:
	pass


## Receives mouse/keyboard events forwarded by the pet.
## Default behaviour for every non-drag state: left-click on the pet picks it up.
func handle_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and pet.contains_point(mb.position):
		machine.transition_to(PetStateMachine.DRAGGED, {"grab_offset": pet.global_position - mb.position})
		get_viewport().set_input_as_handled()


func is_active() -> bool:
	return machine != null and machine.current_state == self
