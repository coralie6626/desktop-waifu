class_name DesktopPet
extends Node2D
## The pet: owns the Spine sprite, speech bubble, context menu and state machine.
## The node's origin is at the character's FEET (bottom-centre), so standing on the
## taskbar simply means `position.y == floor_y`.

## Emitted when a one-shot animation (see one_shot_anims) reaches its end.
signal animation_finished(anim: StringName)

@export_group("Movement")
@export var walk_speed := 90.0
## Dropping the pet within this many pixels above the taskbar makes it SIT.
@export var sit_snap_distance := 140.0
## Used for the fall after being dropped mid-screen (px/s²).
@export var gravity := 2400.0

@export_group("Perching")
## Dropped with the feet up to this many px below a window's top edge still lands on it.
@export var perch_reach := 24.0
## Minimum title bar left on each side of the feet for her to sit there.
@export var perch_margin := 12.0

@export_group("Dialogue")
@export var idle_lines: PackedStringArray = [
	"Hi there!",
	"What are you working on?",
	"Don't forget to drink some water~",
	"*yawn*",
	"I'm keeping an eye on you.",
]
@export var grab_lines: PackedStringArray = ["Hey!", "Wheee~", "Put me down!"]

@export_group("Animation")
## Size of the clickable box, measured up from the feet (unscaled skeleton units).
@export var hit_size := Vector2(92, 176)
## Animations that play once and emit animation_finished; everything else loops.
@export var one_shot_anims: Array[StringName] = [&"idle_action"]

enum MenuId { TALK, SIT, QUIT }

## Area the pet lives in, in window coordinates. Its bottom edge is the taskbar's top edge.
var bounds := Rect2()
var floor_y: float:
	get:
		return bounds.end.y

var _anim_names: Dictionary[StringName, bool] = {}

@onready var sprite: SpineSprite = $Sprite
@onready var bubble: SpeechBubble = $SpeechBubble
@onready var context_menu: PopupMenu = $ContextMenu
@onready var state_machine: PetStateMachine = $StateMachine
@onready var window_tracker: WindowTracker = $WindowTracker


func _ready() -> void:
	for anim: SpineAnimation in sprite.skeleton_data_res.get_animations():
		_anim_names[StringName(anim.get_name())] = true
	sprite.animation_completed.connect(_on_sprite_animation_completed)
	_build_context_menu()
	# Lets you run DesktopPet.tscn on its own (F6) for quick testing.
	if get_parent() == get_tree().root:
		setup(get_viewport_rect())


## Called by Main once the overlay window has its final size.
func setup(play_area: Rect2) -> void:
	bounds = play_area
	position = Vector2(bounds.get_center().x, floor_y)
	state_machine.start(self)


func _process(_delta: float) -> void:
	var rect := get_hit_rect()
	bubble.head_position = Vector2(rect.get_center().x, rect.position.y)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT and bubble.visible and bubble.get_global_rect().has_point(mb.position):
			bubble.hide_message()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and contains_point(mb.position):
			_open_context_menu()
			get_viewport().set_input_as_handled()
			return
	state_machine.handle_input(event)


# --- Dialogue -------------------------------------------------------------------

func say_message(text: String, duration: float = -1.0) -> void:
	bubble.say_message(text, duration)


## Says a random entry from `lines` (defaults to idle_lines).
func say_random_line(lines := PackedStringArray()) -> void:
	if lines.is_empty():
		lines = idle_lines
	if not lines.is_empty():
		say_message(lines[randi() % lines.size()])


# --- Animation helpers ------------------------------------------------------------

func has_anim(anim: StringName) -> bool:
	return _anim_names.has(anim)


## Plays `anim`, or `fallback` if the skeleton doesn't define it.
func play_anim(anim: StringName, fallback: StringName = &"idle") -> void:
	if not has_anim(anim):
		if not has_anim(fallback):
			return
		anim = fallback
	sprite.get_animation_state().set_animation(anim, not one_shot_anims.has(anim), 0)


func _on_sprite_animation_completed(_sprite: SpineSprite, _state: SpineAnimationState, entry: SpineTrackEntry) -> void:
	var anim := StringName(entry.get_animation().get_name())
	if one_shot_anims.has(anim):
		animation_finished.emit(anim)


## Faces the sprite towards `direction` (-1 = left, 1 = right). Only the sprite is
## flipped so the speech bubble never gets mirrored.
func face(direction: float) -> void:
	if not is_zero_approx(direction):
		sprite.scale.x = absf(sprite.scale.x) * signf(direction)


# --- Geometry -----------------------------------------------------------------------

## Screen-space box standing on the skeleton's root (the feet), see hit_size.
func get_hit_rect() -> Rect2:
	var size := hit_size * sprite.global_scale.abs()
	return Rect2(sprite.global_position - Vector2(size.x * 0.5, size.y), size)


## Everything that must stay clickable AND visible (see Main._update_passthrough).
func get_interactive_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = [get_hit_rect()]
	if bubble.visible:
		rects.append(bubble.get_global_rect())
	return rects


func contains_point(point: Vector2) -> bool:
	return get_hit_rect().has_point(point)


func is_near_floor() -> bool:
	return floor_y - position.y <= sit_snap_distance


## The title bar she'd land on if let go now (see WindowTracker.find_landing), or {}.
func find_perch() -> Dictionary:
	return window_tracker.find_landing(position, perch_reach, perch_top_range(), perch_margin)


## (min, max) y a window's top edge may have for her to sit on it: low enough that she
## fits on screen above it, and not so close to the taskbar that the floor would do.
func perch_top_range() -> Vector2:
	return Vector2(bounds.position.y + get_hit_rect().size.y, floor_y - perch_reach)


## Keeps the whole sprite on screen and never below the taskbar.
func clamp_to_bounds() -> void:
	var size := get_hit_rect().size
	position.x = clampf(position.x, bounds.position.x + size.x * 0.5, bounds.end.x - size.x * 0.5)
	position.y = clampf(position.y, bounds.position.y + size.y, floor_y)


# --- Context menu -------------------------------------------------------------------

func _build_context_menu() -> void:
	context_menu.add_item("Say something", MenuId.TALK)
	context_menu.add_item("Sit down", MenuId.SIT)
	context_menu.add_separator()
	context_menu.add_item("Quit", MenuId.QUIT)
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)


func _open_context_menu() -> void:
	# embed_subwindows is off, so the popup is its own OS window placed in screen
	# coordinates and isn't clipped by our passthrough region.
	context_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.TALK:
			say_random_line()
		MenuId.SIT:
			state_machine.transition_to(PetStateMachine.SITTING)
		MenuId.QUIT:
			get_tree().quit()
