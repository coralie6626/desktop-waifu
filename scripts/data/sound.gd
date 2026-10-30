extends Node
## Autoload `Sound`: her sounds, on a Voice and an SFX audio bus whose volumes follow
## Settings audio/voice_volume and audio/sfx_volume (0 to 1).
## Until there are real voice lines, a short synthesised blip plays when she speaks,
## and a two-note chime when a reminder comes due.

const VOICE_BUS := &"Voice"
const SFX_BUS := &"SFX"
const MIX_RATE := 22050

var _blip: AudioStreamWAV
var _chime: AudioStreamWAV
var _voice := AudioStreamPlayer.new()
var _sfx := AudioStreamPlayer.new()


func _ready() -> void:
	for bus in [VOICE_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_voice.bus = VOICE_BUS
	_sfx.bus = SFX_BUS
	add_child(_voice)
	add_child(_sfx)
	_blip = _tone([[880.0, 0.035], [1175.0, 0.045]], 0.25)
	_chime = _tone([[1047.0, 0.16], [1319.0, 0.32]], 0.35)
	Settings.changed.connect(func(key: StringName) -> void:
		if String(key).begins_with("audio/"):
			apply_volumes())
	apply_volumes()


func apply_volumes() -> void:
	_set_volume(VOICE_BUS, Settings.get_value(&"audio/voice_volume"))
	_set_volume(SFX_BUS, Settings.get_value(&"audio/sfx_volume"))


## The little "voice" when a line appears.
func blip() -> void:
	_voice.stream = _blip
	_voice.pitch_scale = randf_range(0.95, 1.08)
	_voice.play()


## When something needs your attention (a reminder, timer or alarm).
func chime() -> void:
	_sfx.stream = _chime
	_sfx.play()


func _set_volume(bus: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(volume, 0.0001, 1.0)))


## Sine notes played one after another, each [frequency, seconds], with a soft fade.
static func _tone(notes: Array, amplitude: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for note: Array in notes:
		var count := int(note[1] * MIX_RATE)
		for i in count:
			var fade := minf(1.0, minf(i / 120.0, (count - i) / (count * 0.6)))
			var sample := sin(TAU * note[0] * i / MIX_RATE) * amplitude * fade
			var value := int(sample * 32767.0)
			data.append(value & 0xFF)
			data.append((value >> 8) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	return stream
