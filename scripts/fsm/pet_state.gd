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
## Default behaviour for every non-drag state: hand them to the pet's gesture detector,
## which reports clicks, double-clicks and pickups (see DesktopPet._on_drag_started).
func handle_input(event: InputEvent) -> void:
	if pet.gestures.handle_input(event):
		get_viewport().set_input_as_handled()


func is_active() -> bool:
	return machine != null and machine.current_state == self
