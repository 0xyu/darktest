extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main_scene := load("res://scenes/world/Main.tscn") as PackedScene
	_expect(main_scene != null, "main scene can be loaded")
	if main_scene == null:
		_quit_with_result()
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var game := main.get_node("GridTest") as GridTest
	var hud := game.hud
	_expect(hud.get_node("Root/TopPanel/Margin/Content/Header/StageLabel").text == "STAGE 01", "HUD displays the current stage")
	_expect(hud.get_node("Root/TopPanel/Margin/Content/PlayerHPRow/PlayerHPBar") is ProgressBar, "HUD displays player HP")
	_expect(hud.get_node("Root/TopPanel/Margin/Content/TargetHPRow/TargetHPBar") is ProgressBar, "HUD displays target HP")
	_expect("MP" in hud.get_node("Root/TopPanel/Margin/Content/CombatInfoLabel").text, "HUD displays movement points")
	_expect(hud.get_node("Root/BottomPanel/Margin/Content/ActionRow/AttackButton") is Button, "HUD has an attack button")
	_expect(hud.get_node("Root/BottomPanel/Margin/Content/ActionRow/ItemButton") is Button, "HUD has an item button")
	_expect(hud.get_node("Root/BottomPanel/Margin/Content/ActionRow/AutoButton") is Button, "HUD has an auto button")

	hud.show_critical_indicator(42)
	var critical_label := hud.get_node("Root/CriticalLabel") as Label
	_expect(critical_label.visible and "42" in critical_label.text, "HUD shows a critical hit indicator")

	game.turn_manager.set_victory()
	await process_frame
	var state_banner := hud.get_node("Root/StateBanner") as PanelContainer
	var state_label := hud.get_node("Root/StateBanner/StateLabel") as Label
	_expect(state_banner.visible and state_label.text == "VICTORY", "HUD displays victory state")

	main.free()
	await process_frame
	var defeat_main := main_scene.instantiate()
	root.add_child(defeat_main)
	await process_frame
	await process_frame
	var defeat_game := defeat_main.get_node("GridTest") as GridTest
	defeat_game.turn_manager.set_defeat()
	await process_frame
	var defeat_hud := defeat_game.hud
	var defeat_banner := defeat_hud.get_node("Root/StateBanner") as PanelContainer
	var defeat_label := defeat_hud.get_node("Root/StateBanner/StateLabel") as Label
	_expect(defeat_banner.visible and defeat_label.text == "DEFEAT", "HUD displays defeat state")

	defeat_main.free()
	await process_frame
	if _failures.is_empty():
		print("Phase 22 smoke test passed.")
	else:
		for failure in _failures:
			push_error(failure)
	_quit_with_result()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append("Smoke test failed: " + description)


func _quit_with_result() -> void:
	quit(0 if _failures.is_empty() else 1)
