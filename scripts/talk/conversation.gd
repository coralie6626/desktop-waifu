class_name Conversation
extends Node
## Plays a scripted conversation in her speech bubble: a list of steps, each with
## "say" (literal text) or "line" (a Dialogue trigger), an optional "anim" reaction, an
## optional "do" action (+ "value"), and optional "choices". A choice has "text", its own
## "do", and "steps" that run when it's picked, after which the outer list carries on.
## A line stays up until it's clicked or its timer runs out. While running she holds
## still (see DesktopPet.is_busy()); picking her up or hiding her cancels it.

## A step or choice asked for an action, e.g. "set_mood" with "tired".
signal action(name: String, value: Variant)

## Lines stay up this many times longer than usual, since there's more to read.
@export var read_time_scale := 1.6
## Pixels between her hit box and the answer menu.
@export var menu_gap := 8.0

var _running := false
var _cancelled := false

@onready var _pet := get_parent() as DesktopPet
@onready var _choices: ChoiceMenu = $"../ChoiceMenu"


func is_running() -> bool:
	return _running


## Runs `steps` to the end. `body_anim` (e.g. "snack") plays meanwhile, and her own
## animation comes back afterwards. Returns false if it was cancelled or a question
## was dismissed.
func run(steps: Array, body_anim: StringName = &"") -> bool:
	if _running:
		cancel()
		await get_tree().process_frame
	_running = true
	_cancelled = false
	var machine := _pet.state_machine
	var state := machine.current_state
	if state.name == PetStateMachine.WANDER:
		machine.transition_to(PetStateMachine.IDLE)
		state = machine.current_state
	var previous_anim := _pet.current_anim()
	if body_anim != &"":
		_pet.play_anim(body_anim)

	var finished := await _run_steps(steps)

	_running = false
	if body_anim != &"" and machine.current_state == state and not _cancelled:
		_pet.play_anim(previous_anim)
	return finished


func cancel() -> void:
	if not _running:
		return
	_cancelled = true
	_choices.hide()
	_pet.bubble.hide_message()


func _run_steps(steps: Array) -> bool:
	for step: Dictionary in steps:
		if _cancelled:
			return false
		if step.has("do"):
			action.emit(step.do, step.get("value"))
		var line := _line_for(step)
		var options: Array = step.get("choices", [])
		if options.is_empty():
			if line.is_empty():
				continue
			_say(line, -1.0)
			await _pet.bubble.closed
			continue

		# A question: keep it up until it's answered.
		if not line.is_empty():
			_say(line, 3600.0)
		var titles := PackedStringArray()
		for option: Dictionary in options:
			titles.append(option.text)
		var index := await _choices.ask(titles, _menu_position())
		if _cancelled or index < 0:
			if not _cancelled:
				_pet.say_line(&"talk_cancel")
			return false
		_pet.bubble.hide_message()
		var option: Dictionary = options[index]
		if option.has("do"):
			action.emit(option.do, option.get("value"))
		if not await _run_steps(option.get("steps", [])):
			return false
	return not _cancelled


func _line_for(step: Dictionary) -> Dictionary:
	if step.has("say"):
		return {"text": step.say, "anim": StringName(step.get("anim", ""))}
	if step.has("line"):
		var line := Dialogue.pick(StringName(step.line))
		if step.has("anim") and not line.is_empty():
			line.anim = StringName(step.anim)
		return line
	return {}


func _say(line: Dictionary, duration: float) -> void:
	if duration <= 0.0:
		var bubble := _pet.bubble
		duration = maxf(bubble.min_duration, line.text.length() * bubble.seconds_per_char) * read_time_scale
	_pet.say_message(line.text, duration)
	if line.anim != &"":
		_pet.play_reaction(line.anim)


## Beside her, level with her chest, in screen coordinates.
func _menu_position() -> Vector2i:
	var rect := _pet.get_hit_rect()
	var local := Vector2(rect.end.x + menu_gap, rect.position.y + rect.size.y * 0.3)
	return get_window().position + Vector2i(local)
