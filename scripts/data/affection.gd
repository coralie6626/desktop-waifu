extends Node
## Autoload `Affection`: how fond she is of you, one number kept in SaveData.
## Pats, talking and check-ins raise it; too much poking and staying away lower it.
## Gains are capped per day so a long patting session can't max her out, and crossing a
## threshold moves her to the next level, which unlocks lines, topics and outfits.

## Emitted after every change, with the amount actually applied.
signal changed(points: int, delta: int)
## Emitted when a gain crosses into a new level (not when she drops back down).
signal level_up(level: int)

## Points needed for each level; level 0 is where everyone starts.
const LEVELS: Array[int] = [0, 25, 75, 175, 350]
const LEVEL_NAMES: PackedStringArray = ["Shy", "Friendly", "Close", "Very close", "Devoted"]
## Most points that can be gained in one calendar day. Losses are never capped.
const DAILY_GAIN_CAP := 30
## Days away before she starts to feel neglected, and the points lost per day after that.
const NEGLECT_GRACE_DAYS := 2
const NEGLECT_PER_DAY := 2
const MAX_NEGLECT_LOSS := 20
## How often "last seen" is refreshed while running, in seconds.
const HEARTBEAT := 300.0

## Whole days since she last ran (0 on the first launch). Read it for greetings.
var days_away := 0

var _heartbeat: Timer


func _ready() -> void:
	var last_seen: int = SaveData.get_value(&"affection/last_seen")
	if last_seen > 0:
		days_away = maxi(0, int((Time.get_unix_time_from_system() - last_seen) / 86400.0))
		var neglected := days_away - NEGLECT_GRACE_DAYS
		if neglected > 0:
			add(-mini(neglected * NEGLECT_PER_DAY, MAX_NEGLECT_LOSS))
	_touch()
	_heartbeat = Timer.new()
	_heartbeat.wait_time = HEARTBEAT
	_heartbeat.timeout.connect(_touch)
	add_child(_heartbeat)
	_heartbeat.start()


func get_points() -> int:
	return SaveData.get_value(&"affection/points")


func get_level() -> int:
	return level_for(get_points())


static func level_for(points: int) -> int:
	var level := 0
	for i in LEVELS.size():
		if points >= LEVELS[i]:
			level = i
	return level


## Changes affection by `amount`, respecting the daily gain cap and never going below
## zero. Returns how much was actually applied.
func add(amount: int) -> int:
	var points := get_points()
	if amount > 0:
		var today := Time.get_date_string_from_system()
		var gained: int = SaveData.get_value(&"affection/gained_today")
		if SaveData.get_value(&"affection/day") != today:
			SaveData.set_value(&"affection/day", today)
			gained = 0
		amount = mini(amount, DAILY_GAIN_CAP - gained)
		if amount <= 0:
			return 0
		SaveData.set_value(&"affection/gained_today", gained + amount)
	else:
		amount = maxi(amount, -points)
		if amount == 0:
			return 0

	var old_level := level_for(points)
	SaveData.set_value(&"affection/points", points + amount)
	changed.emit(points + amount, amount)
	var new_level := level_for(points + amount)
	if new_level > old_level:
		SaveData.unlock_memory("affection_level_%d" % new_level)
		level_up.emit(new_level)
	return amount


func _touch() -> void:
	SaveData.set_value(&"affection/last_seen", int(Time.get_unix_time_from_system()))
