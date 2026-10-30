class_name TrayIcon
extends StatusIndicator
## The pet's icon in the notification area. Left-click shows or hides her; right-click
## opens the menu, which is where the settings live since she can't always be
## right-clicked (hidden, or click-through on).
## The menu is opened by hand rather than through StatusIndicator.menu, so that both
## buttons arrive through the pressed signal and left-click stays free for the toggle.

enum MenuId {
	TOGGLE, NOTES, WARDROBE, SCHEDULE, GAMES, ALWAYS_ON_TOP, CLICK_THROUGH, WATCH_DOWNLOADS,
	HIDE_30, HIDE_UNTIL_RESTART, QUIT,
}

## Volume steps offered in the Volume submenus, in percent.
const VOLUME_STEPS: Array[int] = [0, 25, 50, 75, 100]
## How long "Hide for 30 minutes" hides her, in seconds.
const HIDE_TIME := 30 * 60
## Seconds she waves goodbye before disappearing.
const GOODBYE_TIME := 1.6

## Set by Main.
var pet: DesktopPet

var _menu := PopupMenu.new()
var _time_menu := TimeMenu.new()
var _character_menu := PopupMenu.new()
var _settings_menu := PopupMenu.new()
var _volume_menu := PopupMenu.new()
var _monitor_menu := PopupMenu.new()
var _volume_menus: Dictionary[StringName, PopupMenu] = {}
var _hide_timer := Timer.new()


func _ready() -> void:
	tooltip = ProjectSettings.get_setting("application/config/name")
	for menu in [_menu, _time_menu, _character_menu, _settings_menu, _volume_menu, _monitor_menu]:
		menu.theme = preload("res://ui/menu_theme.tres")

	_menu.add_item("Hide", MenuId.TOGGLE)
	_menu.add_separator()
	_menu.add_item("Notes...", MenuId.NOTES)
	_add_submenu(_menu, _time_menu, "Keep time for me")
	_menu.add_separator()

	_character_menu.add_item("Wardrobe...", MenuId.WARDROBE)
	_character_menu.add_item("Schedule...", MenuId.SCHEDULE)
	_add_submenu(_menu, _character_menu, "Character")

	_settings_menu.add_item("Game whitelist...", MenuId.GAMES)
	_settings_menu.add_check_item("Always on top", MenuId.ALWAYS_ON_TOP)
	_settings_menu.add_check_item("Click-through mode", MenuId.CLICK_THROUGH)
	_settings_menu.add_check_item("Watch my Downloads folder", MenuId.WATCH_DOWNLOADS)
	for bus in [&"voice", &"sfx"]:
		var menu := PopupMenu.new()
		menu.theme = _menu.theme
		for i in VOLUME_STEPS.size():
			menu.add_radio_check_item("%d%%" % VOLUME_STEPS[i], i)
		menu.id_pressed.connect(_on_volume_picked.bind(bus))
		_volume_menus[bus] = menu
		_add_submenu(_volume_menu, menu, "Voice" if bus == &"voice" else "Sound effects")
	_monitor_menu.id_pressed.connect(_on_monitor_picked)
	_add_submenu(_settings_menu, _monitor_menu, "Monitor")
	_add_submenu(_settings_menu, _volume_menu, "Volume")
	_add_submenu(_menu, _settings_menu, "Settings")

	_menu.add_item("Hide for 30 minutes", MenuId.HIDE_30)
	_menu.add_item("Hide until restart", MenuId.HIDE_UNTIL_RESTART)
	_menu.add_separator()
	_menu.add_item("Quit", MenuId.QUIT)

	for menu in [_menu, _character_menu, _settings_menu]:
		menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(_menu)
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_on_hide_timer_timeout)
	add_child(_hide_timer)
	pressed.connect(_on_pressed)


func _on_pressed(mouse_button: int, mouse_position: Vector2i) -> void:
	match mouse_button:
		MOUSE_BUTTON_LEFT:
			_toggle_pet()
		MOUSE_BUTTON_RIGHT:
			_refresh_menu()
			# Screen coordinates; the popup shifts itself up to stay above the taskbar.
			_menu.popup(Rect2i(mouse_position, Vector2i.ZERO))


func _refresh_menu() -> void:
	_menu.set_item_text(_menu.get_item_index(MenuId.TOGGLE), "Hide" if pet.visible else "Show")
	_time_menu.pet = pet
	_fill_monitor_menu()
	_set_checked(_settings_menu, MenuId.ALWAYS_ON_TOP, Settings.get_value(&"window/always_on_top"))
	_set_checked(_settings_menu, MenuId.CLICK_THROUGH, Settings.get_value(&"window/click_through"))
	_set_checked(_settings_menu, MenuId.WATCH_DOWNLOADS, not String(Settings.get_value(&"tools/watch_folder")).is_empty())
	for bus in _volume_menus:
		var volume: float = Settings.get_value(StringName("audio/%s_volume" % bus))
		var menu := _volume_menus[bus]
		for i in VOLUME_STEPS.size():
			menu.set_item_checked(i, roundi(volume * 100.0) == VOLUME_STEPS[i])


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.TOGGLE:
			_toggle_pet()
		MenuId.NOTES:
			Desk.open_notes()
		MenuId.WARDROBE:
			Desk.open_wardrobe()
		MenuId.SCHEDULE:
			Desk.open_schedule()
		MenuId.GAMES:
			Desk.open_games(pet.window_tracker.last_app)
		MenuId.ALWAYS_ON_TOP:
			Settings.set_value(&"window/always_on_top", not Settings.get_value(&"window/always_on_top"))
		MenuId.CLICK_THROUGH:
			Settings.set_value(&"window/click_through", not Settings.get_value(&"window/click_through"))
		MenuId.WATCH_DOWNLOADS:
			var watching := not String(Settings.get_value(&"tools/watch_folder")).is_empty()
			Settings.set_value(&"tools/watch_folder", "" if watching else OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))
		MenuId.HIDE_30:
			hide_pet(HIDE_TIME)
		MenuId.HIDE_UNTIL_RESTART:
			hide_pet(0)
		MenuId.QUIT:
			get_tree().quit()


## Waves goodbye and hides her; after `seconds` (if > 0) she comes back and says so.
func hide_pet(seconds: int) -> void:
	_hide_timer.stop()
	if pet.visible:
		pet.say_line(&"goodbye_timed" if seconds > 0 else &"goodbye")
		pet.play_reaction(&"idle_action")
		await get_tree().create_timer(GOODBYE_TIME).timeout
		pet.set_shown(false)
	if seconds > 0:
		_hide_timer.start(seconds)


func _on_hide_timer_timeout() -> void:
	pet.set_shown(true)
	pet.say_line(&"welcome_back")


## Primary, then each monitor (left to right), then "Follow the mouse"; the item's
## metadata is the window/monitor value.
func _fill_monitor_menu() -> void:
	_monitor_menu.clear()
	var screens := range(DisplayServer.get_screen_count())
	screens.sort_custom(func(a: int, b: int) -> bool: return DisplayServer.screen_get_position(a).x < DisplayServer.screen_get_position(b).x)
	var choices := [["Primary monitor", "primary"]]
	for i in screens.size():
		choices.append(["Monitor %d%s" % [i + 1, " (primary)" if screens[i] == DisplayServer.get_primary_screen() else ""], str(screens[i])])
	choices.append(["Follow the mouse", "follow_mouse"])
	var current: String = Settings.get_value(&"window/monitor")
	for i in choices.size():
		_monitor_menu.add_radio_check_item(choices[i][0], i)
		_monitor_menu.set_item_metadata(i, choices[i][1])
		_monitor_menu.set_item_checked(i, choices[i][1] == current)


func _on_monitor_picked(index: int) -> void:
	Settings.set_value(&"window/monitor", _monitor_menu.get_item_metadata(index))


func _on_volume_picked(index: int, bus: StringName) -> void:
	Settings.set_value(StringName("audio/%s_volume" % bus), VOLUME_STEPS[index] / 100.0)


func _toggle_pet() -> void:
	_hide_timer.stop()
	pet.set_shown(not pet.visible)


static func _add_submenu(parent: PopupMenu, submenu: PopupMenu, label: String) -> void:
	parent.add_child(submenu)
	parent.add_submenu_node_item(label, submenu)


static func _set_checked(menu: PopupMenu, id: int, checked: bool) -> void:
	menu.set_item_checked(menu.get_item_index(id), checked)
