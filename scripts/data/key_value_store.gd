class_name KeyValueStore
extends Node
## Base for the Settings and SaveData autoloads: a flat set of known keys with default
## values, loaded from disk at startup and written back shortly after any change.
## Keys look like "section/name". Subclasses list the keys in _defaults() and decide the
## file format in _read() / _write().

## Emitted after `key` got a new value (also when reset to its default).
signal changed(key: StringName)

var _defaults_cache: Dictionary[StringName, Variant] = {}
var _values: Dictionary[StringName, Variant] = {}
var _save_queued := false


func _init() -> void:
	_defaults_cache = _defaults()
	for key in _defaults_cache:
		_values[key] = _copy(_defaults_cache[key])


func _ready() -> void:
	_load()


func _exit_tree() -> void:
	flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


## Current value of `key`. Arrays and dictionaries are copies: change them, then pass
## them back through set_value() so the change is saved and announced.
func get_value(key: StringName) -> Variant:
	if not _check_key(key):
		return null
	return _copy(_values[key])


func set_value(key: StringName, value: Variant) -> void:
	if not _check_key(key):
		return
	var expected := typeof(_defaults_cache[key])
	if typeof(value) != expected:
		if not _can_convert(typeof(value), expected):
			push_error("%s: '%s' expects %s, got %s" % [name, key, type_string(expected), type_string(typeof(value))])
			return
		value = type_convert(value, expected)
	if _values[key] == value:
		return
	_values[key] = _copy(value)
	_queue_save()
	changed.emit(key)


func reset_value(key: StringName) -> void:
	if _check_key(key):
		set_value(key, _defaults_cache[key])


## A copy of every value, to put back later with restore() (the tests do this).
func snapshot() -> Dictionary:
	return _values.duplicate(true)


## Puts back the values from snapshot() and saves them right away.
func restore(values: Dictionary) -> void:
	for key: StringName in values:
		set_value(key, values[key])
	flush()


func has_key(key: StringName) -> bool:
	return _defaults_cache.has(key)


## Writes pending changes now instead of at the end of the frame.
func flush() -> void:
	if not _save_queued:
		return
	_save_queued = false
	var err := _write(_values)
	if err != OK:
		push_error("%s: saving failed (%s)" % [name, error_string(err)])


# --- For subclasses -------------------------------------------------------------------

## Every key this store knows, with its default value. Its type is the key's type.
func _defaults() -> Dictionary[StringName, Variant]:
	return {}


## Returns whatever was on disk as {key: value}; missing or unknown keys are fine.
func _read() -> Dictionary:
	return {}


func _write(_data: Dictionary[StringName, Variant]) -> Error:
	return ERR_UNAVAILABLE


## Writes through a temporary file and renames it over `path`, so a crash mid-write
## never leaves a half-written file behind.
static func _replace_file(path: String, write: Callable) -> Error:
	var tmp := path + ".tmp"
	var err: Error = write.call(tmp)
	if err != OK:
		return err
	return DirAccess.rename_absolute(tmp, path)


# --- Internals --------------------------------------------------------------------------

func _load() -> void:
	var stored := _read()
	for key in stored:
		var key_name := StringName(key)
		if not _defaults_cache.has(key_name):
			continue # Left over from an older version.
		var value: Variant = stored[key]
		var expected := typeof(_defaults_cache[key_name])
		if typeof(value) != expected:
			# JSON turns ints into floats and packed arrays into plain ones.
			if not _can_convert(typeof(value), expected):
				push_warning("%s: ignoring stored '%s', expected %s" % [name, key, type_string(expected)])
				continue
			value = type_convert(value, expected)
		_values[key_name] = value


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	# Batches a burst of changes (e.g. dragging a volume slider) into one write.
	flush.call_deferred()


func _check_key(key: StringName) -> bool:
	if _defaults_cache.has(key):
		return true
	push_error("%s: unknown key '%s'" % [name, key])
	return false


## Numbers convert between int and float, and lists between Array and packed arrays.
static func _can_convert(from: int, to: int) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if from in numbers and to in numbers:
		return true
	return _is_list(from) and _is_list(to)


static func _is_list(type: int) -> bool:
	return type == TYPE_ARRAY or (type >= TYPE_PACKED_BYTE_ARRAY and type <= TYPE_PACKED_VECTOR4_ARRAY)


static func _copy(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	if _is_list(typeof(value)):
		return value.duplicate()
	return value
