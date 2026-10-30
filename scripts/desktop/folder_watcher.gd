class_name FolderWatcher
extends Node
## Watches the folder in Settings tools/watch_folder ("" = off; the tray offers the
## Downloads folder) and has her say so when files appear in it: "Your download
## finished!". Godot can't watch folders, so a long-lived PowerShell helper runs a
## FileSystemWatcher and prints each new file name; a worker thread reads them.
## Browsers download to a temporary name and rename it at the end, so renames count
## and temporary names are ignored. Files arriving close together get one line.

## Emitted (on the main thread) for every new file, after filtering.
signal file_appeared(file_name: String)

## Extensions of files that are still being downloaded or written.
const TEMPORARY: PackedStringArray = ["crdownload", "part", "partial", "tmp", "download", "opdownload"]
## Seconds to gather files before she says something.
const GATHER_TIME := 2.5

const HELPER := r"""
$ErrorActionPreference = 'Stop'
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = '__PATH__'
$watcher.IncludeSubdirectories = $false
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName
while ($true) {
	$change = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Created -bor [System.IO.WatcherChangeTypes]::Renamed, 1000)
	if (-not $change.TimedOut) {
		[Console]::Out.WriteLine($change.Name)
		[Console]::Out.Flush()
	}
}
"""

## The folder being watched now, or "".
var watching := ""

var _pid := -1
var _stdio: FileAccess
var _thread: Thread
var _gathered := PackedStringArray()
var _gather_timer := Timer.new()

@onready var _pet := get_parent() as DesktopPet


func _ready() -> void:
	_gather_timer.one_shot = true
	_gather_timer.timeout.connect(_announce)
	add_child(_gather_timer)
	file_appeared.connect(_on_file_appeared)
	Settings.changed.connect(func(key: StringName) -> void:
		if key == &"tools/watch_folder":
			watch(Settings.get_value(key)))
	watch(Settings.get_value(&"tools/watch_folder"))


func _exit_tree() -> void:
	stop()


## Starts watching `path` (stops watching anything else); "" just stops.
func watch(path: String) -> void:
	if path == watching:
		return
	stop()
	if path.is_empty() or OS.get_name() != "Windows":
		return
	if not DirAccess.dir_exists_absolute(path):
		push_warning("FolderWatcher: %s doesn't exist" % path)
		return
	var script := HELPER.replace("__PATH__", path.replace("'", "''"))
	var info := OS.execute_with_pipe("powershell.exe", [
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer()),
	])
	if info.is_empty():
		push_warning("FolderWatcher: couldn't start PowerShell")
		return
	watching = path
	_pid = info["pid"]
	_stdio = info["stdio"]
	_thread = Thread.new()
	_thread.start(_read_lines.bind(_stdio, _pid, _on_line))


func stop() -> void:
	if _thread == null:
		return
	OS.kill(_pid)
	_thread.wait_to_finish()
	_thread = null
	watching = ""


## Whether `file_name` is a finished file rather than a download in progress.
static func is_finished(file_name: String) -> bool:
	if file_name.begins_with("~") or file_name.begins_with("."):
		return false
	return not TEMPORARY.has(file_name.get_extension().to_lower())


## Reads the helper's output on a worker thread. It touches nothing but the pipe and the
## callback (made on the main thread), since nodes can't be used from other threads.
## get_line() blocks until a line comes; once the helper is killed it returns "".
static func _read_lines(stdio: FileAccess, pid: int, deliver: Callable) -> void:
	while true:
		var line := stdio.get_line()
		if line.is_empty():
			if not OS.is_process_running(pid):
				return
			continue
		deliver.call_deferred(line)


func _on_line(line: String) -> void:
	var file_name := line.strip_edges()
	if is_finished(file_name):
		file_appeared.emit(file_name)


func _on_file_appeared(file_name: String) -> void:
	if not _gathered.has(file_name):
		_gathered.append(file_name)
	_gather_timer.start(GATHER_TIME)


func _announce() -> void:
	if _gathered.size() == 1:
		_pet.say_line(&"download_done", -1.0, {"file": _gathered[0]})
	elif _gathered.size() > 1:
		_pet.say_line(&"downloads_done", -1.0, {"count": _gathered.size()})
	_gathered.clear()
