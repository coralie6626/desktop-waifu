class_name DesktopPet
extends Node2D
## The pet: owns the Spine sprite, speech bubble, context menu and state machine.
## The node's origin is at the character's FEET (bottom-centre), so standing on the
## taskbar simply means `position.y == floor_y`.

## Emitted when a one-shot animation (see one_shot_anims) reaches its end.
signal animation_finished(anim: StringName)

## Spine track for reactions (expressions like "happy" or "pat"). They layer over the
## body animation on track 0, so she can smile while she walks or sits.
const REACTION_TRACK := 1

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

@export_group("Animation")
## Size of the clickable box, measured up from the feet (unscaled skeleton units).
@export var hit_size := Vector2(92, 176)
## The clickable box while she lies on the taskbar (sleeping, watching), with room above
## her head for the z's.
@export var lying_hit_size := Vector2(240, 150)
## Animations that play once and emit animation_finished; everything else loops.
@export var one_shot_anims: Array[StringName] = [&"idle_action"]
## Seconds a reaction takes to fade in and out.
@export var reaction_mix := 0.15

enum MenuId { TALK, SIT, HIDE, QUIT }

## Area the pet lives in, in window coordinates. Its bottom edge is the taskbar's top edge.
var bounds := Rect2()
var floor_y: float:
	get:
		return bounds.end.y

## Set by states where she lies down, so the hit box fits the pose.
var lying := false

var _anim_names: Dictionary[StringName, bool] = {}

@onready var sprite: SpineSprite = $Sprite
@onready var bubble: SpeechBubble = $SpeechBubble
@onready var context_menu: PopupMenu = $ContextMenu
@onready var state_machine: PetStateMachine = $StateMachine
@onready var window_tracker: WindowTracker = $WindowTracker
@onready var gestures: PetGestures = $Gestures
@onready var reactions: PetReactions = $Reactions
@onready var conversation: Conversation = $Conversation
@onready var talk_menu: TalkMenu = $TalkMenu
@onready var choice_menu: ChoiceMenu = $ChoiceMenu
@onready var announcer: PetAnnouncer = $Announcer
@onready var wardrobe: Wardrobe = $Wardrobe
@onready var sleep_schedule: SleepSchedule = $SleepSchedule
@onready var game_watcher: GameWatcher = $GameWatcher
@onready var zzz: ZzzEffect = $Zzz


func _ready() -> void:
	for anim: SpineAnimation in sprite.skeleton_data_res.get_animations():
		_anim_names[StringName(anim.get_name())] = true
	sprite.animation_completed.connect(_on_sprite_animation_completed)
	gestures.drag_started.connect(_on_drag_started)
	gestures.double_clicked.connect(_on_double_clicked)
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


## Hides her (e.g. from the tray) or brings her back. While hidden she isn't drawn,
## can't be clicked and is paused, so she picks up where she left off.
func set_shown(shown: bool) -> void:
	if shown == visible:
		return
	if not shown:
		gestures.cancel()
		conversation.cancel()
		stop_reaction()
		bubble.hide()
		context_menu.hide()
		talk_menu.hide()
	visible = shown
	process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED


## True while she's being patted, talked to or announcing a reminder: states hold
## still and skip idle chatter.
func is_busy() -> bool:
	return gestures.is_patting() or conversation.is_running() or announcer.is_active()


# --- Gestures (see PetGestures; clicks and pats go to PetReactions) ------------------

func _on_drag_started(press_position: Vector2) -> void:
	state_machine.transition_to(PetStateMachine.DRAGGED, {"grab_offset": global_position - press_position})


func _on_double_clicked(_position: Vector2) -> void:
	talk_menu.open()


# --- Dialogue -------------------------------------------------------------------

func say_message(text: String, duration: float = -1.0) -> void:
	bubble.say_message(text, duration)
	Sound.blip()


## Says a line for `trigger` from Dialogue, with its reaction; `args` fill {placeholders}.
## Returns false if no line fits right now.
func say_line(trigger: StringName, duration: float = -1.0, args: Dictionary = {}) -> bool:
	var line := Dialogue.pick(trigger)
	if line.is_empty():
		return false
	say_message(line.text.format(args) if not args.is_empty() else line.text, duration)
	if line.anim != &"":
		play_reaction(line.anim)
	return true


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


## The body animation playing now (track 0), or &"" if none.
func current_anim() -> StringName:
	var entry := sprite.get_animation_state().get_current(0)
	return StringName(entry.get_animation().get_name()) if entry else &""


## Plays a reaction over the current body animation (see REACTION_TRACK). One-shot
## reactions fade out by themselves; looping ones (like "pat") run until stop_reaction().
func play_reaction(anim: StringName, loop := false) -> void:
	if not has_anim(anim):
		return
	var state := sprite.get_animation_state()
	var current := state.get_current(REACTION_TRACK)
	if current == null or current.get_animation().get_name() == "<empty>":
		# Start from an empty animation so the reaction fades in instead of popping.
		state.set_empty_animation(REACTION_TRACK, 0.0)
		state.add_animation(anim, 0.0, loop, REACTION_TRACK).set_mix_duration(reaction_mix)
	else:
		state.set_animation(anim, loop, REACTION_TRACK)


func stop_reaction() -> void:
	sprite.get_animation_state().set_empty_animation(REACTION_TRACK, reaction_mix)


func _on_sprite_animation_completed(_sprite: SpineSprite, _state: SpineAnimationState, entry: SpineTrackEntry) -> void:
	var anim := StringName(entry.get_animation().get_name())
	if entry.get_track_index() == REACTION_TRACK:
		if not entry.get_loop() and anim != &"<empty>":
			stop_reaction()
	elif one_shot_anims.has(anim):
		animation_finished.emit(anim)


## Faces the sprite towards `direction` (-1 = left, 1 = right). Only the sprite is
## flipped so the speech bubble never gets mirrored.
func face(direction: float) -> void:
	if not is_zero_approx(direction):
		sprite.scale.x = absf(sprite.scale.x) * signf(direction)


# --- Geometry -----------------------------------------------------------------------

## Screen-space box standing on the skeleton's root (the feet), see hit_size.
func get_hit_rect() -> Rect2:
	var size := (lying_hit_size if lying else hit_size) * sprite.global_scale.abs()
	return Rect2(sprite.global_position - Vector2(size.x * 0.5, size.y), size)


## Everything that must stay clickable AND visible (see Main._update_passthrough).
## Empty while she's hidden.
func get_interactive_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if not visible:
		return rects
	rects.append(get_hit_rect())
	if bubble.visible:
		rects.append(bubble.get_global_rect())
	return rects


func contains_point(point: Vector2) -> bool:
	return get_hit_rect().has_point(point)


## &"head", &"face", &"chest", &"hands", &"skirt" or &"body" (see BodyParts).
func get_body_part(point: Vector2) -> StringName:
	return BodyParts.find(sprite, point)


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
	context_menu.theme = preload("res://ui/menu_theme.tres")
	context_menu.add_item("Talk...", MenuId.TALK)
	context_menu.add_item("Sit down", MenuId.SIT)
	context_menu.add_separator()
	# Only where there's a tray icon to bring her back with.
	if DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		context_menu.add_item("Hide", MenuId.HIDE)
	context_menu.add_item("Quit", MenuId.QUIT)
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)


func _open_context_menu() -> void:
	# embed_subwindows is off, so the popup is its own OS window placed in screen
	# coordinates and isn't clipped by our passthrough region.
	context_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.TALK:
			talk_menu.open()
		MenuId.SIT:
			state_machine.transition_to(PetStateMachine.SITTING)
		MenuId.HIDE:
			set_shown(false)
		MenuId.QUIT:
			get_tree().quit()
