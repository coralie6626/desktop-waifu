class_name Mood
## The daily "How was your day?" check-in: one answer per calendar day, kept in
## SaveData's talk/mood_history as {"YYYY-MM-DD": mood}.

const MOODS: PackedStringArray = ["great", "okay", "tired", "stressed", "bad"]
## Affection for checking in, once a day.
const CHECK_IN_AFFECTION := 2


## Today's answer, or "" if she hasn't asked yet today.
static func today() -> String:
	return SaveData.get_value(&"talk/mood_history").get(Time.get_date_string_from_system(), "")


## Saves today's answer. The first check-in of the day also raises affection.
static func record(mood: String) -> void:
	if not MOODS.has(mood):
		push_error("Mood: unknown mood '%s'" % mood)
		return
	var history: Dictionary = SaveData.get_value(&"talk/mood_history")
	var date := Time.get_date_string_from_system()
	var first_today := not history.has(date)
	history[date] = mood
	SaveData.set_value(&"talk/mood_history", history)
	SaveData.unlock_memory("first_checkin")
	if first_today:
		Affection.add(CHECK_IN_AFFECTION)
