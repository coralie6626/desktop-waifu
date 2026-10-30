class_name SnackTime
## Snack Time topics: a few are offered each day, picked from data/talk/snack_topics.json
## with the date as the random seed, unseen topics first. Today's offer is saved, so
## finishing a topic doesn't reshuffle the rest of the day. Finished topics unlock in
## talk/unlocked_topics for the Memories gallery.

const TOPICS_PATH := "res://data/talk/snack_topics.json"
## Topics offered per day.
const PER_DAY := 3
## Affection for finishing a topic.
const TOPIC_AFFECTION := 2

static var _topics: Array = []


## Every topic, as in the data file.
static func all_topics() -> Array:
	if _topics.is_empty():
		var data: Variant = Dialogue.load_json(TOPICS_PATH)
		if data is Dictionary:
			_topics = data.get("topics", [])
	return _topics


static func find_topic(id: String) -> Dictionary:
	for topic: Dictionary in all_topics():
		if topic.id == id:
			return topic
	return {}


## Today's topics that haven't been talked about yet today.
static func remaining_today() -> Array[Dictionary]:
	_refresh_offer()
	var done: PackedStringArray = SaveData.get_value(&"talk/snack_done")
	var remaining: Array[Dictionary] = []
	for id in SaveData.get_value(&"talk/snack_offer"):
		var topic := find_topic(id)
		if not topic.is_empty() and not done.has(id):
			remaining.append(topic)
	return remaining


## Call when a topic has been talked through.
static func finish(id: String) -> void:
	var done: PackedStringArray = SaveData.get_value(&"talk/snack_done")
	if not done.has(id):
		done.append(id)
		SaveData.set_value(&"talk/snack_done", done)
	var unlocked: PackedStringArray = SaveData.get_value(&"talk/unlocked_topics")
	if not unlocked.has(id):
		unlocked.append(id)
		SaveData.set_value(&"talk/unlocked_topics", unlocked)
	Affection.add(TOPIC_AFFECTION)


## Picks today's offer the first time it's needed each day.
static func _refresh_offer() -> void:
	var today := Time.get_date_string_from_system()
	if SaveData.get_value(&"talk/snack_day") == today:
		return
	SaveData.set_value(&"talk/snack_day", today)
	SaveData.set_value(&"talk/snack_done", PackedStringArray())
	SaveData.set_value(&"talk/snack_offer", pick_offer(today, Affection.get_level(), SaveData.get_value(&"talk/unlocked_topics")))


## The topic ids offered on `date`: those her affection `level` allows, unseen first,
## shuffled with the date as the seed.
static func pick_offer(date: String, level: int, seen: PackedStringArray) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(date)
	var unseen: Array[String] = []
	var again: Array[String] = []
	for topic: Dictionary in all_topics():
		if int(topic.get("min_level", 0)) > level:
			continue
		(again if seen.has(topic.id) else unseen).append(topic.id)
	_shuffle(unseen, rng)
	_shuffle(again, rng)
	var offer := PackedStringArray(unseen + again)
	return offer.slice(0, PER_DAY)


## Array.shuffle() uses the global RNG, so shuffle with our seeded one instead.
static func _shuffle(items: Array[String], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := items[i]
		items[i] = items[j]
		items[j] = swap
