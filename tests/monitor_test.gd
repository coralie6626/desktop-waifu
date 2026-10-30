extends Node
## Self-check for multiple monitors: finding the monitor under a point, the monitor
## setting, moving the overlay (and her) to another monitor, dragging her across and
## "follow the mouse". Needs a real display with two or more monitors; headless (one
## fake screen) it only checks the single-monitor basics. Run this scene (F6), or
## godot res://tests/monitor_test.tscn (exit code 1 on failure). Settings are put back.

var _failures := 0


func _ready() -> void:
	var stores := [SaveData.snapshot(), Settings.snapshot()]
	Settings.set_value(&"schedule/bedtime", "")
	Settings.set_value(&"window/monitor", "primary")

	_test_lookup()
	if DisplayServer.get_screen_count() >= 2:
		await _test_moving()
	else:
		print("SKIP  moving between monitors: only one screen here")

	for i in 2:
		await get_tree().process_frame
	SaveData.restore(stores[0])
	Settings.restore(stores[1])
	if _failures == 0:
		print("All monitor checks passed.")
	else:
		printerr("%d monitor check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_lookup() -> void:
	var all_found := true
	for i in DisplayServer.get_screen_count():
		var centre := DisplayServer.screen_get_position(i) + DisplayServer.screen_get_size(i) / 2
		all_found = all_found and load("res://scripts/main.gd").screen_at(centre) == i
	_check("each monitor is found under its centre", all_found)
	_check("a point off every monitor is in a gap", load("res://scripts/main.gd").screen_at(Vector2i(-100000, -100000)) == -1)
	var main_script: Script = load("res://scripts/main.gd")
	_check("'primary' means the primary monitor", main_script.chosen_screen() == DisplayServer.get_primary_screen())
	Settings.set_value(&"window/monitor", "99")
	_check("a monitor that isn't there falls back to the primary", main_script.chosen_screen() == DisplayServer.get_primary_screen())
	Settings.set_value(&"window/monitor", "primary")


func _test_moving() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var pet: DesktopPet = main.get_node(^"DesktopPet")
	pet.game_watcher.process_mode = Node.PROCESS_MODE_DISABLED
	var window := get_window()
	var primary := DisplayServer.get_primary_screen()
	var other := 1 if primary == 0 else 0
	_check("she starts on the primary monitor", main.screen == primary
		and window.position == DisplayServer.screen_get_usable_rect(primary).position)

	main.move_to_screen(other)
	var area := DisplayServer.screen_get_usable_rect(other)
	_check("the overlay moves to the other monitor", main.screen == other and window.position == area.position)
	_check("and fits it", window.size.x == area.size.x and absi(window.size.y - area.size.y) <= 1)
	_check("her play area follows", pet.bounds.size.is_equal_approx(Vector2(window.size)))
	_check("and she's on it", Rect2(Vector2.ZERO, pet.bounds.size).grow(1).has_point(pet.position))

	Settings.set_value(&"window/monitor", str(primary))
	_check("picking a monitor in the settings moves her there", main.screen == primary)

	pet.state_machine.transition_to(PetStateMachine.DRAGGED, {"grab_offset": Vector2.ZERO})
	var other_centre := DisplayServer.screen_get_position(other) + DisplayServer.screen_get_size(other) / 2
	main.follow_drag(other_centre)
	_check("dragging her across carries the overlay along", main.screen == other)
	# (Dragged puts her under the real cursor on the next frame; here she just stays inside.)
	_check("and keeps her inside the new monitor", Rect2(Vector2.ZERO, pet.bounds.size).grow(1).has_point(pet.position))
	main.follow_drag(DisplayServer.screen_get_position(other) + Vector2i(10, 10))
	_check("staying on the same monitor doesn't move it", main.screen == other)

	pet.state_machine.transition_to(PetStateMachine.IDLE)
	var primary_point := DisplayServer.screen_get_position(primary) + Vector2i(600, 300)
	main.follow_mouse(primary_point)
	_check("'follow the mouse' brings her over", main.screen == primary)
	_check("to stand below the mouse", absf(Vector2(window.position).x + pet.position.x - primary_point.x) < 1.0
		and pet.position.y == pet.floor_y)
	main.queue_free()
	await get_tree().process_frame


func _check(description: String, ok: bool) -> void:
	if ok:
		print("PASS  ", description)
	else:
		_failures += 1
		printerr("FAIL  ", description)
