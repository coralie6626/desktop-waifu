extends Node
## Root controller. Turns the game window into a transparent, borderless, always-on-top
## overlay covering the monitor's usable area (everything except the taskbar), and keeps
## the window's clickable region glued to the pet so clicks elsewhere reach the desktop.
## Always-on-top and click-through mode follow Settings (window/*).

## Extra clickable margin around the pet and bubble, in pixels.
@export var hit_padding := 6.0

var _last_rects: Array[Rect2] = []
## Whether the window is currently set to let every click through.
var _click_through := false

@onready var pet: DesktopPet = $DesktopPet
@onready var tray: TrayIcon = $TrayIcon


func _ready() -> void:
	tray.pet = pet
	if Engine.is_embedded_in_editor():
		push_warning("Running embedded in the editor's Game tab: transparency and click-through " +
			"won't work. Disable 'Embed Game on Next Play' in the Game tab and run again.")
	var area := _setup_overlay_window()
	# Window coordinates: (0, 0) is the usable area's top-left; its bottom is the taskbar top.
	pet.setup(Rect2(Vector2.ZERO, Vector2(area.size)))
	Settings.changed.connect(_on_setting_changed)
	_apply_window_settings()


func _process(_delta: float) -> void:
	_update_passthrough()


## Project settings already request most of this; setting it again at runtime makes the
## behaviour explicit and survives someone tweaking the settings.
func _setup_overlay_window() -> Rect2i:
	var window := get_window()
	window.borderless = true
	window.always_on_top = Settings.get_value(&"window/always_on_top")
	window.transparent = true
	window.unresizable = true
	get_viewport().transparent_bg = true

	var screen := window.current_screen
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var full := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	# Windows treats a borderless window that exactly covers a monitor as fullscreen and can
	# drop per-pixel transparency (happens with an auto-hidden taskbar). Stay 1 px short.
	if usable == full:
		usable.size.y -= 1

	window.position = usable.position
	window.size = usable.size
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
	if key in [&"window/always_on_top", &"window/click_through"]:
		_apply_window_settings()


func _apply_window_settings() -> void:
	get_window().always_on_top = Settings.get_value(&"window/always_on_top")
	var click_through: bool = Settings.get_value(&"window/click_through")
	if click_through != _click_through:
		_click_through = click_through
		# Needs Win32 window styles, which the tracker's helper can set.
		pet.window_tracker.set_click_through(get_window(), click_through)
