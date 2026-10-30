class_name TrayIcon
extends StatusIndicator
## The pet's icon in the notification area. Left-click shows or hides her; right-click
## opens a menu, which is where settings will go (F-S1) since she can't always be
## right-clicked (hidden, or click-through on).
## The menu is opened by hand rather than through StatusIndicator.menu, so that both
## buttons arrive through the pressed signal and left-click stays free for the toggle.

enum MenuId { TOGGLE, QUIT }

## Set by Main.
var pet: DesktopPet

var _menu := PopupMenu.new()


func _ready() -> void:
	tooltip = ProjectSettings.get_setting("application/config/name")
	_menu.theme = preload("res://ui/menu_theme.tres")
	_menu.add_item("Hide", MenuId.TOGGLE)
	_menu.add_separator()
	_menu.add_item("Quit", MenuId.QUIT)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(_menu)
	pressed.connect(_on_pressed)


func _on_pressed(mouse_button: int, mouse_position: Vector2i) -> void:
	match mouse_button:
		MOUSE_BUTTON_LEFT:
			_toggle_pet()
		MOUSE_BUTTON_RIGHT:
			_menu.set_item_text(_menu.get_item_index(MenuId.TOGGLE), "Hide" if pet.visible else "Show")
			# Screen coordinates; the popup shifts itself up to stay above the taskbar.
			_menu.popup(Rect2i(mouse_position, Vector2i.ZERO))


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.TOGGLE:
			_toggle_pet()
		MenuId.QUIT:
			get_tree().quit()


func _toggle_pet() -> void:
	pet.set_shown(not pet.visible)
