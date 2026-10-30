class_name TalkMenu
extends PopupMenu
## The Talk menu, opened by double-clicking her (or from her right-click menu). Its own
## OS window like the context menu, so it isn't clipped by the click region.
## Snack Time and the mood check-in run as Conversations.

enum Id { SNACK, MOOD, CHAT }

const MOOD_CHECKIN_PATH := "res://data/talk/mood_checkin.json"

@onready var _pet := get_parent() as DesktopPet
@onready var _conversation: Conversation = $"../Conversation"


func _ready() -> void:
	theme = preload("res://ui/menu_theme.tres")
	add_item("Snack time", Id.SNACK)
	add_item("How was your day?", Id.MOOD)
	add_item("Say something", Id.CHAT)
	id_pressed.connect(_on_id_pressed)
	_conversation.action.connect(_on_action)


## Opens the menu at the cursor, with a little "yes?" from her.
func open() -> void:
	if _conversation.is_running():
		return
	set_item_text(get_item_index(Id.SNACK), "Snack time (%d left today)" % SnackTime.remaining_today().size())
	_pet.say_line(&"talk_open")
	popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_id_pressed(id: int) -> void:
	_pet.bubble.hide_message()
	match id:
		Id.SNACK:
			start_snack_time()
		Id.MOOD:
			start_mood_check_in()
		Id.CHAT:
			_pet.say_line(&"idle")


func start_snack_time() -> void:
	var topics := SnackTime.remaining_today()
	if topics.is_empty():
		_pet.say_line(&"snack_done_all")
		return
	var choices: Array = []
	for topic in topics:
		choices.append({
			"text": topic.title,
			"steps": topic.steps + [{"line": "snack_end", "do": "finish_topic", "value": topic.id}],
		})
	choices.append({"text": "Just snack together", "steps": [{"line": "snack_quiet"}]})
	await _conversation.run([{"line": "snack_intro", "choices": choices}], &"snack")


func start_mood_check_in() -> void:
	var data: Variant = Dialogue.load_json(MOOD_CHECKIN_PATH)
	if not data is Dictionary:
		return
	var steps: Array = data.get("steps", [])
	if not Mood.today().is_empty():
		steps = [{"line": "mood_again"}] + steps
	await _conversation.run(steps)


func _on_action(action: String, value: Variant) -> void:
	match action:
		"set_mood":
			Mood.record(value)
		"finish_topic":
			SnackTime.finish(value)
		_:
			push_warning("TalkMenu: unknown action '%s'" % action)
