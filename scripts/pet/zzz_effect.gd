class_name ZzzEffect
extends Node2D
## Little z's drifting up and fading out above her head while she sleeps. They stay
## inside her lying hit box, since anything outside the click region isn't drawn.

## Seconds between z's.
@export var interval := 1.1
## Where they start, in the head bone's space (Spine style, y up).
@export var start_offset := Vector2(30, 96)
@export var rise := 34.0
@export var color := Color(0.35, 0.3, 0.55)

var _timer := Timer.new()
var _count := 0

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	_timer.wait_time = interval
	_timer.timeout.connect(_spawn)
	add_child(_timer)


func start() -> void:
	_count = 0
	_spawn()
	_timer.start()


func stop() -> void:
	_timer.stop()
	for child in get_children():
		if child is Label:
			child.queue_free()


func _spawn() -> void:
	_count += 1
	var label := Label.new()
	label.text = "Z" if _count % 3 == 0 else "z"
	label.add_theme_font_size_override(&"font_size", 14 + (_count % 3) * 3)
	label.add_theme_color_override(&"font_color", color)
	add_child(label)
	var head := _pet.sprite.get_global_bone_transform(&"head")
	var start := to_local(head * Vector2(start_offset.x, -start_offset.y)) + Vector2((_count % 2) * 8.0, 0)
	label.position = start
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position", start + Vector2(10, -rise), interval * 2.0)
	tween.tween_property(label, "modulate:a", 0.0, interval * 2.0).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)
