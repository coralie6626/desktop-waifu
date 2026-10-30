class_name PetStateMachine
extends Node
## Minimal node-based finite state machine.
## Every child that extends PetState is registered as a state, keyed by its node name.

signal state_changed(from_state: StringName, to_state: StringName)

const IDLE := &"Idle"
const WANDER := &"Wander"
const DRAGGED := &"Dragged"
const SITTING := &"Sitting"
const PERCHED := &"Perched"
const ANNOUNCE := &"Announce"
const SLEEPING := &"Sleeping"
const WATCHING := &"Watching"
const HOP := &"Hop"

@export var initial_state: PetState

var current_state: PetState
var _states: Dictionary[StringName, PetState] = {}


## Registers the child states, injects the pet reference and enters the initial state.
func start(pet: DesktopPet) -> void:
	_states.clear()
	for child in get_children():
		if child is PetState:
			_states[child.name] = child
			child.pet = pet
			child.machine = self

	assert(not _states.is_empty(), "PetStateMachine has no PetState children.")
	if current_state:
		current_state.exit()
	current_state = initial_state if initial_state else _states.values()[0]
	current_state.enter()
	state_changed.emit(&"", current_state.name)


func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	var next: PetState = _states.get(state_name)
	if next == null:
		push_error("PetStateMachine: unknown state '%s'" % state_name)
		return

	var previous := current_state
	if previous:
		previous.exit()
	current_state = next
	current_state.enter(msg)
	state_changed.emit(previous.name if previous else &"", state_name)


func handle_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)
