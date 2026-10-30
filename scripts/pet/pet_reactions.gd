class_name PetReactions
extends Node
## How she responds to touch: headpats, and a click on each part of her (see BodyParts).
## Poking her face, chest or skirt too often in a short time makes her annoyed for a
## while, and every click gets a pout until it wears off; a headpat makes up for it.

@export_group("Headpats")
## Strokes (direction changes) per affection point.
@export var strokes_per_point := 6
## Strokes between happy lines while she's being patted.
@export var strokes_per_line := 10
@export var pat_lines: PackedStringArray = [
	"Mmm~ that's nice...",
	"More pats, please~",
	"Ehehe...",
	"You're really good at this.",
]
@export var pat_end_lines: PackedStringArray = ["Thanks for the pats!", "That was nice~", "Aww, done already?"]
@export var first_pat_line := "O-oh! A headpat? ...I like it."

@export_group("Clicks")
@export var head_lines: PackedStringArray = ["Hehe~", "Hm? What is it?", "That tickles!"]
@export var face_lines: PackedStringArray = ["Hey! My nose!", "Eek!", "W-what was that for?"]
@export var flustered_lines: PackedStringArray = ["H-hey! Not there!", "Wh-what are you doing?!", "Hands to yourself!"]
@export var hand_lines: PackedStringArray = ["*holds your cursor*", "Your hand is warm~", "High five!"]

@export_group("Annoyance")
## This many pokes (face, chest, skirt) within annoy_window seconds makes her annoyed.
@export var annoy_pokes := 4
@export var annoy_window := 10.0
@export var annoyed_time := 30.0
## Affection lost each time she gets annoyed.
@export var annoyed_penalty := 2
@export var annoyed_lines: PackedStringArray = ["Hmph. I'm not talking to you.", "Stop poking me!", "..."]
@export var forgiven_lines: PackedStringArray = ["...Okay, you're forgiven.", "Fine. Just this once."]

@export_group("Affection")
## Said on reaching each level (index = level; level 0 is the start and never reached).
@export var level_up_lines: PackedStringArray = [
	"",
	"I think I'm starting to like it here.",
	"You're really nice to me, you know?",
	"I'm always happy when you're around.",
	"I... really like spending time with you.",
]

var _strokes := 0
var _poke_times: Array[float] = []
var _annoyed_until := 0.0

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	var gestures: PetGestures = _pet.get_node(^"Gestures")
	gestures.clicked.connect(_on_clicked)
	gestures.pat_started.connect(_on_pat_started)
	gestures.patted.connect(_on_patted)
	gestures.pat_ended.connect(_on_pat_ended)
	Affection.level_up.connect(_on_level_up)


func is_annoyed() -> bool:
	return _now() < _annoyed_until


func _on_clicked(position: Vector2) -> void:
	if is_annoyed():
		_react(&"pout", annoyed_lines)
		return
	match _pet.get_body_part(position):
		&"head":
			_react(&"happy", head_lines)
		&"hands":
			_react(&"happy", hand_lines)
			Affection.add(1)
		&"face":
			if not _poke():
				_react(&"surprised", face_lines)
		&"chest", &"skirt":
			if not _poke():
				_react(&"shy", flustered_lines)
		_:
			_pet.say_random_line()


## Counts a poke. Returns true if it was the last straw (she's now annoyed and has
## already reacted).
func _poke() -> bool:
	var now := _now()
	_poke_times.append(now)
	while _poke_times[0] < now - annoy_window:
		_poke_times.pop_front()
	if _poke_times.size() < annoy_pokes:
		return false
	_poke_times.clear()
	_annoyed_until = now + annoyed_time
	Affection.add(-annoyed_penalty)
	_react(&"pout", annoyed_lines)
	return true


func _on_pat_started() -> void:
	_strokes = 0
	# She stops to enjoy it instead of walking off from under the cursor.
	if _pet.state_machine.current_state.name == PetStateMachine.WANDER:
		_pet.state_machine.transition_to(PetStateMachine.IDLE)
	_pet.play_reaction(&"pat", true)
	if is_annoyed():
		_annoyed_until = 0.0
		_poke_times.clear()
		_pet.say_random_line(forgiven_lines)
	elif SaveData.unlock_memory("first_headpat"):
		_pet.say_message(first_pat_line)


func _on_patted() -> void:
	_strokes += 1
	if _strokes % strokes_per_point == 0:
		Affection.add(1)
	if _strokes % strokes_per_line == 0:
		_pet.say_random_line(pat_lines)


func _on_pat_ended() -> void:
	_pet.stop_reaction()
	if _strokes >= strokes_per_point:
		_pet.say_random_line(pat_end_lines)


func _on_level_up(level: int) -> void:
	if level < level_up_lines.size() and not level_up_lines[level].is_empty():
		_pet.play_reaction(&"happy")
		_pet.say_message(level_up_lines[level], 5.0)


func _react(anim: StringName, lines: PackedStringArray) -> void:
	_pet.play_reaction(anim)
	_pet.say_random_line(lines)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
