class_name SpeechBubble
extends PanelContainer
## Dialogue bubble that pops up above the pet's head and hides itself after a timer.
## It positions itself in window coordinates above `head_position`, which the pet
## updates every frame, and stays clamped inside the screen.

@export var max_text_width := 240.0
@export var min_duration := 2.0
@export var seconds_per_char := 0.07
## Pixels between the top of the pet and the bottom of the bubble.
@export var gap := 10.0
@export var screen_margin := 4.0

## Top-centre of the pet, in global coordinates. Set by DesktopPet.
var head_position := Vector2.ZERO

var _tween: Tween

@onready var _label: Label = $Label
@onready var _timer: Timer = $HideTimer


func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer.one_shot = true
	_timer.timeout.connect(hide_message)


func _process(_delta: float) -> void:
	if visible:
		# Re-fit every frame: autowrapped labels settle their height a frame late.
		reset_size()
		pivot_offset = Vector2(size.x * 0.5, size.y)
		_reposition()


## Shows `text` above the pet. `duration` <= 0 picks a duration based on text length.
func say_message(text: String, duration: float = -1.0) -> void:
	_label.text = text

	# Shrink-wrap short lines, wrap long ones at max_text_width.
	var font := _label.get_theme_font(&"font")
	var font_size := _label.get_theme_font_size(&"font_size")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_label.custom_minimum_size.x = minf(ceilf(text_width) + 2.0, max_text_width)
	reset_size()
	pivot_offset = Vector2(size.x * 0.5, size.y)
	_reposition()
	show()

	# Little "pop" animation.
	if _tween:
		_tween.kill()
	scale = Vector2(0.8, 0.8)
	modulate.a = 0.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)

	_timer.start(duration if duration > 0.0 else maxf(min_duration, text.length() * seconds_per_char))


func hide_message() -> void:
	_timer.stop()
	if not visible:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_tween.tween_callback(hide)


func _reposition() -> void:
	var screen_size := get_viewport_rect().size
	var target := head_position - Vector2(size.x * 0.5, size.y + gap)
	target.x = clampf(target.x, screen_margin, screen_size.x - size.x - screen_margin)
	target.y = maxf(target.y, screen_margin)
	global_position = target
