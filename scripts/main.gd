extends Node
## Root controller. Turns the game window into a transparent, borderless, always-on-top
## overlay covering one monitor's usable area (everything except the taskbar), and keeps
## the window's clickable region glued to the pet so clicks elsewhere reach the desktop.
## Always-on-top and click-through mode follow Settings (window/*).
## With several monitors the overlay moves to the one she's on: the one chosen in
## window/monitor ("primary", a screen index, or "follow_mouse"), and whichever one
## she's dragged onto.

## Extra clickable margin around the pet and bubble, in pixels.
@export var hit_padding := 6.0
## How often "follow the mouse" checks which monitor the mouse is on, in seconds.
@export var follow_interval := 1.0

## The monitor the overlay is on.
var screen := -1

var _last_rects: Array[Rect2] = []
## Whether the window is currently set to let every click through.
var _click_through := false
var _follow_left := 0.0

@onready var pet: DesktopPet = $DesktopPet
@onready var tray: TrayIcon = $TrayIcon


func _ready() -> void:
	tray.pet = pet
	if Engine.is_embedded_in_editor():
		push_warning("Running embedded in the editor's Game tab: transparency and click-through " +
			"won't work. Disable 'Embed Game on Next Play' in the Game tab and run again.")
	var area := _setup_overlay_window(chosen_screen())
	# Window coordinates: (0, 0) is the usable area's top-left; its bottom is the taskbar top.
	pet.setup(Rect2(Vector2.ZERO, Vector2(area.size)))
	Settings.changed.connect(_on_setting_changed)
	_apply_window_settings()


func _process(delta: float) -> void:
	if pet.state_machine.current_state.name == PetStateMachine.DRAGGED:
		follow_drag(DisplayServer.mouse_get_position())
	elif Settings.get_value(&"window/monitor") == "follow_mouse":
		_follow_left -= delta
		if _follow_left <= 0.0:
			_follow_left = follow_interval
			follow_mouse(DisplayServer.mouse_get_position())
	_update_passthrough()


## The monitor picked in Settings window/monitor (the primary one by default, or if the
## one picked isn't connected any more). For "follow_mouse", the one under the mouse.
static func chosen_screen() -> int:
	var choice: String = Settings.get_value(&"window/monitor")
	if choice == "follow_mouse":
		var under_mouse := screen_at(DisplayServer.mouse_get_position())
		return under_mouse if under_mouse >= 0 else DisplayServer.get_primary_screen()
	if choice.is_valid_int() and int(choice) >= 0 and int(choice) < DisplayServer.get_screen_count():
		return int(choice)
	return DisplayServer.get_primary_screen()


## The monitor containing `point` (desktop coordinates), or -1 if it's in a gap.
static func screen_at(point: Vector2i) -> int:
	for i in DisplayServer.get_screen_count():
		if Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)).has_point(point):
			return i
	return -1


## Moves the overlay onto monitor `index`. She keeps her place on the desktop if that's
## on the new monitor (being dragged across), otherwise she's put back inside it.
func move_to_screen(index: int) -> void:
	if index == screen or index < 0 or index >= DisplayServer.get_screen_count():
		return
	var on_desktop := Vector2(get_window().position) + pet.position
	var area := _setup_overlay_window(index)
	pet.set_bounds(Rect2(Vector2.ZERO, Vector2(area.size)))
	pet.position = on_desktop - Vector2(area.position)
	pet.clamp_to_bounds()
	_last_rects.clear() # Force a new click region for the new window size.


## While she's being dragged: carries the overlay along when the cursor crosses onto
## another monitor.
func follow_drag(mouse: Vector2i) -> void:
	var under_mouse := screen_at(mouse)
	if under_mouse >= 0 and under_mouse != screen:
		move_to_screen(under_mouse)


## "Follow the mouse": when she's free and the mouse is on another monitor, she comes
## over and stands on its taskbar below the mouse.
func follow_mouse(mouse: Vector2i) -> void:
	var under_mouse := screen_at(mouse)
	var state := pet.state_machine.current_state.name
	if under_mouse < 0 or under_mouse == screen or pet.is_busy() or not pet.visible:
		return
	if state not in [PetStateMachine.IDLE, PetStateMachine.WANDER, PetStateMachine.SITTING]:
		return
	move_to_screen(under_mouse)
	pet.position = Vector2(mouse.x - get_window().position.x, pet.floor_y)
	pet.clamp_to_bounds()
	pet.state_machine.transition_to(PetStateMachine.IDLE)


## Covers monitor `index`. Project settings already request most of this; setting it
## again at runtime makes the behaviour explicit and survives someone tweaking them.
func _setup_overlay_window(index: int) -> Rect2i:
	var window := get_window()
	window.borderless = true
	window.always_on_top = Settings.get_value(&"window/always_on_top")
	window.transparent = true
	window.unresizable = true
	get_viewport().transparent_bg = true

	var usable := DisplayServer.screen_get_usable_rect(index)
	var full := Rect2i(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index))
	# Windows treats a borderless window that exactly covers a monitor as fullscreen and can
	# drop per-pixel transparency (happens with an auto-hidden taskbar). Stay 1 px short.
	if usable == full:
		usable.size.y -= 1

	window.position = usable.position
	window.size = usable.size
	screen = index
	return usable


func _update_passthrough() -> void:
	var rects := pet.get_interactive_rects()
	for i in rects.size():
		rects[i] = rects[i].grow(hit_padding)
	if rects == _last_rects:
		return # Only touch the OS window region when something actually moved.
	_last_rects = rects
	DisplayServer.window_set_mouse_passthrough(_build_polygon(rects), get_window().get_window_id())


## Windows accepts a single passthrough polygon, and everything outside it is clipped
## visually as well (SetWindowRgn) — so the bubble must be part of the same outline.
func _build_polygon(rects: Array[Rect2]) -> PackedVector2Array:
	if rects.is_empty():
		# An empty polygon would make the whole window clickable again, so use a speck
		# outside the window: nothing is left to click or see.
		return _rect_to_polygon(Rect2(-2, -2, 1, 1))
	var polygon := _rect_to_polygon(rects[0])
	for i in range(1, rects.size()):
		var merged := Geometry2D.merge_polygons(polygon, _rect_to_polygon(rects[i]))
		if merged.size() != 1:
			# Shapes don't overlap: fall back to one box around everything.
			var bounds := rects[0]
			for rect in rects:
				bounds = bounds.merge(rect)
			return _rect_to_polygon(bounds)
		polygon = merged[0]
	return polygon


func _rect_to_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


func _on_setting_changed(key: StringName) -> void:
	if key == &"window/monitor":
		move_to_screen(chosen_screen())
	elif key in [&"window/always_on_top", &"window/click_through"]:
		_apply_window_settings()


func _apply_window_settings() -> void:
	get_window().always_on_top = Settings.get_value(&"window/always_on_top")
	var click_through: bool = Settings.get_value(&"window/click_through")
	if click_through != _click_through:
		_click_through = click_through
		# Needs Win32 window styles, which the tracker's helper can set.
		pet.window_tracker.set_click_through(get_window(), click_through)
