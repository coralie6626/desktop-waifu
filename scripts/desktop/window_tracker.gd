class_name WindowTracker
extends Node
## Keeps a snapshot of the other apps' top-level windows so the pet can sit on their
## title bars (Windows only; elsewhere the snapshot just stays empty).
## Win32 isn't reachable from GDScript, so a small PowerShell helper does the
## EnumWindows call. It's started once, lives for the whole session and answers a
## "list" request on stdin with one JSON line (it also sets click-through on our own
## window, see set_click_through). Requests run on a worker thread so the
## pet never stalls while PowerShell starts up or answers.

## Emitted on the main thread whenever `windows` has been refreshed.
signal updated

## Other apps' visible windows in z-order (topmost first), each as
## {"id": int, "rect": Rect2} in the pet window's coordinates.
var windows: Array[Dictionary] = []
## The window in front as {"exe": "name.exe", "fullscreen": bool}, or {} when it's the
## desktop or taskbar. Clicking the pet doesn't count: it keeps the previous value.
var foreground: Dictionary = {}
## The executable of the last app that was in front (not us, not the desktop), or "".
var last_app := ""

var _pid := -1
var _stdio: FileAccess
var _thread: Thread
var _semaphore := Semaphore.new()
var _mutex := Mutex.new()
## Lines waiting to be sent to the helper ("list", "clickthrough <hwnd> <0|1>").
var _commands := PackedStringArray()
var _pending := false
var _quitting := false

# Prints {"ox", "oy", "w": [[hwnd, left, top, right, bottom], ...], "fg": ...} in physical
# pixels. "ox"/"oy" is the virtual desktop's top-left, which Godot uses as its screen
# origin. "fg" is {"exe", "full"} for the foreground window, "self" for ours, or null.
const HELPER := r"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Nobody reads stderr; keep it from filling up.
try {
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PetWindows {
	delegate bool EnumProc(IntPtr hwnd, IntPtr lparam);
	[StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
	[DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lparam);
	[DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
	[DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
	[DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
	[DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
	[DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint key, byte alpha, uint flags);
	[DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr hwnd);
	[DllImport("user32.dll")] static extern int GetClassName(IntPtr hwnd, StringBuilder name, int size);
	[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
	[DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
	[DllImport("user32.dll")] static extern IntPtr SetProcessDpiAwarenessContext(IntPtr context);
	[DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT rect, int size);
	[DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);
	[StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int Size; public RECT Monitor, Work; public uint Flags; }
	[DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
	[DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
	[DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
	[DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

	// Per-monitor DPI aware, like Godot, so both sides agree on physical pixels.
	public static void Init() { SetProcessDpiAwarenessContext(new IntPtr(-4)); }

	public static string List(uint skipPid) {
		var sb = new StringBuilder();
		sb.Append("{\"ox\":").Append(GetSystemMetrics(76)).Append(",\"oy\":").Append(GetSystemMetrics(77)).Append(",\"w\":[");
		bool first = true;
		EnumWindows(delegate (IntPtr hwnd, IntPtr lparam) {
			if (!IsWindowVisible(hwnd) || IsIconic(hwnd) || GetWindowTextLength(hwnd) == 0) return true;
			uint pid;
			GetWindowThreadProcessId(hwnd, out pid);
			if (pid == skipPid) return true;
			if ((GetWindowLong(hwnd, -20) & 0x80) != 0) return true; // WS_EX_TOOLWINDOW
			int cloaked; // hidden UWP / other-desktop windows
			if (DwmGetWindowAttribute(hwnd, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
			var cls = new StringBuilder(64);
			GetClassName(hwnd, cls, 64);
			string c = cls.ToString();
			if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return true;
			RECT r; // visible frame, without the invisible resize borders
			if (DwmGetWindowAttribute(hwnd, 9, out r, 16) != 0) return true;
			if (r.R - r.L < 50 || r.B - r.T < 30) return true;
			if (!first) sb.Append(',');
			first = false;
			sb.Append('[').Append(hwnd.ToInt64()).Append(',').Append(r.L).Append(',').Append(r.T)
				.Append(',').Append(r.R).Append(',').Append(r.B).Append(']');
			return true;
		}, IntPtr.Zero);
		return sb.Append("],\"fg\":").Append(Foreground(skipPid)).Append('}').ToString();
	}

	// Lets every click through `hwnd` (WS_EX_TRANSPARENT needs WS_EX_LAYERED to reach
	// other apps; full opacity keeps it looking the same), or undoes that.
	public static string ClickThrough(long hwnd, bool on) {
		IntPtr h = new IntPtr(hwnd);
		int ex = GetWindowLong(h, -20);
		if (on) {
			SetWindowLong(h, -20, ex | 0x20 | 0x80000);
			SetLayeredWindowAttributes(h, 0, 255, 2);
		} else {
			SetWindowLong(h, -20, ex & ~0x20 & ~0x80000);
		}
		return "ok";
	}

	// The foreground window's executable, and whether it covers its whole monitor.
	static string Foreground(uint skipPid) {
		IntPtr hwnd = GetForegroundWindow();
		if (hwnd == IntPtr.Zero) return "null";
		uint pid;
		GetWindowThreadProcessId(hwnd, out pid);
		if (pid == skipPid) return "\"self\"";
		var cls = new StringBuilder(64);
		GetClassName(hwnd, cls, 64);
		string c = cls.ToString();
		if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return "null";
		string exe = "";
		try { exe = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName + ".exe"; } catch {}
		bool full = false;
		RECT r;
		var info = new MONITORINFO();
		info.Size = Marshal.SizeOf(typeof(MONITORINFO));
		if (GetWindowRect(hwnd, out r) && GetMonitorInfo(MonitorFromWindow(hwnd, 2), ref info))
			full = r.L <= info.Monitor.L && r.T <= info.Monitor.T && r.R >= info.Monitor.R && r.B >= info.Monitor.B;
		return "{\"exe\":\"" + exe.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\",\"full\":" + (full ? "true" : "false") + "}";
	}
}
'@
[PetWindows]::Init()
} catch {}
while ($null -ne ($line = [Console]::In.ReadLine())) {
	try {
		if ($line.StartsWith("clickthrough ")) {
			$p = $line.Split(" ")
			$reply = [PetWindows]::ClickThrough([long]$p[1], $p[2] -eq "1")
		} else {
			$reply = [PetWindows]::List(__PID__)
		}
	} catch { $reply = '{}' }
	[Console]::Out.WriteLine($reply)
	[Console]::Out.Flush()
}
"""


func _ready() -> void:
	if OS.get_name() != "Windows":
		return
	var script := HELPER.replace("__PID__", str(OS.get_process_id()))
	var info := OS.execute_with_pipe("powershell.exe", [
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer()),
	])
	if info.is_empty():
		push_warning("WindowTracker: couldn't start PowerShell; the pet won't sit on windows.")
		return
	_pid = info["pid"]
	_stdio = info["stdio"]
	_thread = Thread.new()
	_thread.start(_worker)
	request_update() # Warm up: the first reply waits for PowerShell to compile the helper.


func _exit_tree() -> void:
	if _thread == null:
		return
	_quitting = true
	OS.kill(_pid) # Unblocks a worker stuck in get_line().
	_semaphore.post()
	_thread.wait_to_finish()


## Asks the helper for a fresh snapshot; `updated` fires when it arrives.
## Ignored while a request is already in flight.
func request_update() -> void:
	if _thread == null or _pending:
		return
	_pending = true
	_send("list")


## Makes `window` ignore the mouse entirely (clicks reach whatever is under it), or
## undoes that. Needs Win32, so it goes through the helper too.
func set_click_through(window: Window, on: bool) -> void:
	var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id())
	_send("clickthrough %d %d" % [hwnd, int(on)])


func _send(command: String) -> void:
	if _thread == null:
		return
	_mutex.lock()
	_commands.append(command)
	_mutex.unlock()
	_semaphore.post()


## The window with this id from the latest snapshot, or {} if it's gone.
func find_window(id: int) -> Dictionary:
	for window in windows:
		if window.id == id:
			return window
	return {}


## The first title bar `feet` would land on when falling straight down: the highest
## window top at or below the feet (they may already be up to `reach` px past it),
## within `top_range` (min, max), with `margin` px of title bar on both sides of the
## feet, and not hidden behind another window at that spot. Returns {} if none.
func find_landing(feet: Vector2, reach: float, top_range: Vector2, margin: float) -> Dictionary:
	var best := {}
	for i in windows.size():
		var rect: Rect2 = windows[i].rect
		var top := rect.position.y
		if top < feet.y - reach or top < top_range.x or top > top_range.y:
			continue
		if feet.x < rect.position.x + margin or feet.x > rect.end.x - margin:
			continue
		if _is_covered(Vector2(feet.x, top + 1.0), i):
			continue
		if best.is_empty() or top < best.rect.position.y:
			best = windows[i]
	return best


func _is_covered(point: Vector2, index: int) -> bool:
	for j in index:
		if windows[j].rect.has_point(point):
			return true
	return false


func _worker() -> void:
	while true:
		_semaphore.wait()
		if _quitting:
			return
		_mutex.lock()
		var command: String = _commands[0] if not _commands.is_empty() else ""
		if not _commands.is_empty():
			_commands.remove_at(0)
		_mutex.unlock()
		if command.is_empty():
			continue
		_stdio.store_line(command)
		_stdio.flush()
		var line := _stdio.get_line()
		if _stdio.eof_reached():
			return # Helper died; keep the last snapshot.
		if command == "list":
			_on_reply.call_deferred(line)


func _on_reply(line: String) -> void:
	_pending = false
	var data: Variant = JSON.parse_string(line.strip_edges())
	if not data is Dictionary or not data.has("w"):
		return
	# Win32 pixels -> Godot screen (origin at the virtual desktop's top-left) -> our window.
	var offset := Vector2(data.ox, data.oy) + Vector2(get_window().position)
	windows.clear()
	for w: Array in data.w:
		var rect := Rect2(Vector2(w[1], w[2]) - offset, Vector2(w[3] - w[1], w[4] - w[2]))
		windows.append({"id": int(w[0]), "rect": rect})
	var fg: Variant = data.get("fg")
	if fg is Dictionary:
		foreground = {"exe": String(fg.get("exe", "")), "fullscreen": bool(fg.get("full", false))}
		if not foreground.exe.is_empty():
			last_app = foreground.exe
	elif fg != "self":
		foreground = {}
	updated.emit()
