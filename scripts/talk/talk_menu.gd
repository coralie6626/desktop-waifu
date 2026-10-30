class_name TalkMenu
extends PopupMenu
## The Talk menu, opened by double-clicking her (or from her right-click menu). Its own
## OS window like the context menu, so it isn't clipped by the click region.
## Snack Time, the mood check-in and feelings run as Conversations; the scratchpad and
## "Keep time for me" open the Desk tools; Music taps the media keys.

enum Id { SNACK, MOOD, FEELINGS, CHAT, MEMORIES, NOTES }
enum MusicId { PLAY_PAUSE, NEXT, PREVIOUS }

## Windows virtual key codes for the media keys.
const MEDIA_KEYS := {MusicId.PLAY_PAUSE: 0xB3, MusicId.NEXT: 0xB0, MusicId.PREVIOUS: 0xB1}

const MOOD_CHECKIN_PATH := "res://data/talk/mood_checkin.json"
const FEELINGS_PATH := "res://data/talk/feelings.json"

@onready var _pet := get_parent() as DesktopPet
@onready var _conversation: Conversation = $"../Conversation"


func _ready() -> void:
	theme = preload("res://ui/menu_theme.tres")
	add_item("Snack time", Id.SNACK)
	add_item("How was your day?", Id.MOOD)
	add_item("Talk about feelings", Id.FEELINGS)
	add_item("Say something", Id.CHAT)
	add_item("Memories...", Id.MEMORIES)
	add_separator()
	add_item("Jot something down", Id.NOTES)
	var time_menu := TimeMenu.new()
	time_menu.pet = _pet
	add_child(time_menu)
	add_submenu_node_item("Keep time for me", time_menu)
	var music_menu := PopupMenu.new()
	music_menu.theme = theme
	music_menu.add_item("Play / pause", MusicId.PLAY_PAUSE)
	music_menu.add_item("Next song", MusicId.NEXT)
	music_menu.add_item("Previous song", MusicId.PREVIOUS)
	music_menu.id_pressed.connect(press_media_key)
	add_child(music_menu)
	add_submenu_node_item("Music", music_menu)
	id_pressed.connect(_on_id_pressed)
	_conversation.action.connect(_on_action)


## Opens the menu at the cursor, with a little "yes?" from her.
func open() -> void:
	if _pet.is_busy():
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
		Id.FEELINGS:
			start_feelings()
		Id.MEMORIES:
			Desk.open_memories(_pet)
		Id.NOTES:
			Desk.open_notes()
		Id.CHAT:
			_pet.say_line(&"idle")


## Works with Spotify, browsers and most players: it's the keyboard's media key.
func press_media_key(id: int) -> void:
	_pet.window_tracker.press_key(MEDIA_KEYS[id])
	_pet.say_line(&"music_next" if id != MusicId.PLAY_PAUSE else &"music_toggle")
	_pet.play_reaction(&"dance")


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


func start_feelings() -> void:
	var data: Variant = Dialogue.load_json(FEELINGS_PATH)
	if data is Dictionary:
		await _conversation.run(data.get("steps", []))


func _on_action(action: String, value: Variant) -> void:
	match action:
		"set_mood":
			Mood.record(value)
		"feelings_done":
			SaveData.unlock_memory("first_feelings")
			Affection.add(1)
		"finish_topic":
			SnackTime.finish(value)
		_:
			pass # Someone else's action (e.g. SleepSchedule's "go_to_sleep").
