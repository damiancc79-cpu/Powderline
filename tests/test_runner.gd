extends SceneTree

## Dependency-free acceptance checks. Run with:
## Godot --headless --path . --script res://tests/test_runner.gd

const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"steer_left", &"steer_right", &"jump",
	&"trick_one", &"trick_two", &"tuck_grab", &"restart", &"pause",
	&"cycle_weather", &"toggle_debug",
]
const REQUIRED_SCENES: Array[String] = [
	"res://scenes/main/main.tscn",
	"res://scenes/courses/mountain_course.tscn",
	"res://scenes/player/skier.tscn",
	"res://scenes/ui/game_ui.tscn",
]

var _failures: Array[String] = []
var _passes: int = 0


func _init() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("\nPOWDERLINE ACCEPTANCE CHECKS")
	_test_required_input_actions()
	_test_required_resources_load()
	await _test_player_contract()
	await _test_trick_combinations()
	await _test_trick_recognition_catalog()
	await _test_score_and_combo_policy()
	await _test_landing_classification()
	await _test_save_manager_malformed_data()
	await _test_course_contract()
	await _test_weather_contract()
	_test_external_attribution()
	print("\nResult: %d passed, %d failed" % [_passes, _failures.size()])
	for failure: String in _failures:
		print("  FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_required_input_actions() -> void:
	for action: StringName in REQUIRED_ACTIONS:
		_check(InputMap.has_action(action), "Input action exists: %s" % action)
		if InputMap.has_action(action):
			_check(not InputMap.action_get_events(action).is_empty(), "Input action has bindings: %s" % action)


func _test_required_resources_load() -> void:
	for path: String in REQUIRED_SCENES:
		_check(ResourceLoader.exists(path), "Required scene exists: %s" % path)
		if ResourceLoader.exists(path):
			_check(load(path) is PackedScene, "Required scene parses: %s" % path)
	for path: String in [
		"res://resources/tuning/default_ski_tuning.tres",
		"res://resources/surfaces/fresh_powder.tres",
		"res://resources/surfaces/packed_snow.tres",
		"res://resources/surfaces/existing_tracks.tres",
		"res://resources/surfaces/ice.tres",
	]:
		_check(ResourceLoader.exists(path) and load(path) != null, "Resource parses: %s" % path)


func _test_player_contract() -> void:
	if not ResourceLoader.exists("res://scenes/player/skier.tscn"):
		_check(false, "Player scene available for contract test")
		return
	var packed := load("res://scenes/player/skier.tscn") as PackedScene
	var player: Node = packed.instantiate()
	get_root().add_child(player)
	await physics_frame
	_check(player is CharacterBody3D, "Player root is a custom CharacterBody3D")
	for node_name: String in ["GroundProbes", "TrickController", "CrashController", "LandingEvaluator", "ScoreManager", "VisualRoot"]:
		_check(player.get_node_or_null(node_name) != null, "Player component exists: %s" % node_name)
	_check(player.find_child("Camera3D", true, false) != null, "Player includes readable chase camera")
	_check(player.has_method("restart_from_checkpoint") and player.has_method("apply_weather_force"), "Player exposes recovery and weather APIs")
	player.queue_free()
	await process_frame


func _test_trick_combinations() -> void:
	var cases: Array[Dictionary] = [
		{"buttons": [&"trick_one", &"steer_left"], "field": "spin_degrees", "expect": 180, "name": "Q + A spin left"},
		{"buttons": [&"trick_one", &"steer_right"], "field": "spin_degrees", "expect": 180, "name": "Q + D spin right"},
		{"buttons": [&"trick_two", &"move_forward"], "field": "flip_degrees", "expect": 360, "name": "E + W front flip"},
		{"buttons": [&"trick_two", &"move_back"], "field": "flip_degrees", "expect": 360, "name": "E + S backflip"},
		{"buttons": [&"trick_one", &"trick_two"], "field": "did_grab", "expect": true, "name": "Q + E grab"},
		{"buttons": [&"tuck_grab", &"steer_left"], "field": "tweak_count", "expect": 1, "name": "Shift + A tweak"},
		{"buttons": [&"tuck_grab", &"steer_right"], "field": "tweak_count", "expect": 1, "name": "Shift + D tweak"},
	]
	for test_case: Dictionary in cases:
		var controller: Node = (load("res://scripts/player/trick_controller.gd") as GDScript).new()
		controller.set("tuning", load("res://resources/tuning/default_ski_tuning.tres"))
		get_root().add_child(controller)
		for action: StringName in test_case["buttons"]:
			Input.action_press(action)
		# Rotations need enough held time for a complete recognized milestone.
		var duration := 1.0 if test_case["field"] == "flip_degrees" else 0.55
		controller.call("physics_tick", duration, true, true)
		var snapshot: Dictionary = controller.call("current_snapshot")
		for action: StringName in test_case["buttons"]:
			Input.action_release(action)
		var actual: Variant = snapshot.get(test_case["field"])
		if actual is int or actual is float:
			_check(float(actual) >= float(test_case["expect"]), String(test_case["name"]))
		else:
			_check(actual == test_case["expect"], String(test_case["name"]))
		controller.queue_free()
		await process_frame


func _test_trick_recognition_catalog() -> void:
	var controller: Node = (load("res://scripts/player/trick_controller.gd") as GDScript).new()
	controller.set("tuning", load("res://resources/tuning/default_ski_tuning.tres"))
	get_root().add_child(controller)
	for degrees: int in [180, 360, 540, 720]:
		controller.call("begin_airborne")
		controller.set("spin_degrees_signed", float(degrees))
		var snapshot: Dictionary = controller.call("current_snapshot")
		_check(int(snapshot.get("spin_degrees", 0)) == degrees and String(snapshot.get("display_name", "")).contains(str(degrees)), "Recognizes %d spin" % degrees)
	controller.call("begin_airborne")
	controller.set("flip_degrees_signed", 360.0)
	var front: Dictionary = controller.call("current_snapshot")
	_check(String(front.get("display_name", "")).contains("Front Flip"), "Recognizes front flip")
	controller.call("begin_airborne")
	controller.set("flip_degrees_signed", -360.0)
	var back: Dictionary = controller.call("current_snapshot")
	_check(String(back.get("display_name", "")).contains("Backflip"), "Recognizes backflip")
	controller.call("begin_airborne")
	controller.set("spin_degrees_signed", 360.0)
	controller.set("did_grab", true)
	var combined: Dictionary = controller.call("current_snapshot")
	_check(String(combined.get("display_name", "")).contains("Spin") and String(combined.get("display_name", "")).contains("Grab"), "Recognizes grab combined with spin")
	controller.queue_free()
	await process_frame


func _test_score_and_combo_policy() -> void:
	var score: Node = (load("res://scripts/scoring/score_manager.gd") as GDScript).new()
	var combo: Node = (load("res://scripts/scoring/combo_manager.gd") as GDScript).new()
	combo.name = "ComboManager"
	score.add_child(combo)
	score.set("combo_manager", combo)
	get_root().add_child(score)
	await process_frame
	score.call("begin_run")
	var snapshot := {
		"has_trick": true,
		"display_name": "360 Spin + Grab",
		"trick_key": &"spin360_grab",
		"spin_degrees": 360,
		"flip_degrees": 0,
		"did_grab": true,
		"tweak_count": 0,
		"airtime": 1.0,
	}
	var calculated := int(score.call("calculate_trick_points", snapshot))
	_check(calculated == 750, "Trick score formula (360 + grab + combo + airtime)")
	var landing := {"success": true, "perfect": false, "multiplier": 1.0}
	var first_bank := int(score.call("resolve_landing", snapshot, landing))
	var second_bank := int(score.call("resolve_landing", snapshot, landing))
	_check(first_bank > 0, "Successful landing banks provisional trick points")
	_check(second_bank < first_bank, "Duplicate trick receives score reduction")
	combo.call("commit_event", &"near_miss")
	score.call("register_crash", &"test_crash")
	_check(int(combo.get("chain_count")) == 0 and is_equal_approx(float(combo.get("multiplier")), 1.0), "Crash clears combo chain")
	var before_failed := int(score.get("score"))
	score.call("preview_trick", snapshot)
	var failed_bank := int(score.call("resolve_landing", snapshot, {"success": false, "reason": &"sideways"}))
	_check(failed_bank == 0 and int(score.get("score")) == before_failed, "Failed landing never banks trick points")
	score.queue_free()
	await process_frame


func _test_landing_classification() -> void:
	var evaluator: Node = (load("res://scripts/scoring/landing_evaluator.gd") as GDScript).new()
	get_root().add_child(evaluator)
	var tuning: Resource = load("res://resources/tuning/default_ski_tuning.tres")
	var clean: Dictionary = evaluator.call(
		"evaluate", 7.0, Vector3.UP, Vector3.FORWARD, Vector3(0, -7, -12), Vector3.UP, tuning
	)
	var sideways: Dictionary = evaluator.call(
		"evaluate", 9.0, Vector3.UP, Vector3.RIGHT, Vector3(0, -9, -15), Vector3.UP, tuning
	)
	var inverted: Dictionary = evaluator.call(
		"evaluate", 9.0, Vector3.DOWN, Vector3.FORWARD, Vector3(0, -9, -15), Vector3.UP, tuning
	)
	_check(bool(clean.get("success")) and bool(clean.get("perfect")), "Clean aligned landing classification")
	_check(not bool(sideways.get("success")) and sideways.get("reason") == &"sideways_landing", "Sideways landing classification")
	_check(not bool(inverted.get("success")), "Inverted landing causes failure")
	evaluator.queue_free()
	await process_frame


func _test_save_manager_malformed_data() -> void:
	var path := "user://powderline-test-malformed.cfg"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Test can create isolated malformed save")
		return
	file.store_string("[settings\ncontroller_deadzone=totally_unclosed(\n")
	file.close()
	var manager: Node = (load("res://autoload/save_manager.gd") as GDScript).new()
	get_root().add_child(manager)
	await process_frame
	var loaded := bool(manager.call("load_data", path))
	var settings: Dictionary = manager.call("get_settings")
	_check(not loaded, "Malformed save is rejected without a crash")
	_check(is_equal_approx(float(settings.get("controller_deadzone", -1.0)), 0.20), "Malformed save falls back to defaults")
	manager.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await process_frame


func _test_course_contract() -> void:
	if not ResourceLoader.exists("res://scenes/courses/mountain_course.tscn"):
		_check(false, "Course scene available for contract test")
		return
	var packed := load("res://scenes/courses/mountain_course.tscn") as PackedScene
	var course: Node = packed.instantiate()
	get_root().add_child(course)
	await process_frame
	_check(course.has_method("get_spawn_transform"), "Course exposes start transform")
	_check(course.has_method("get_surface_sample"), "Course exposes snow surface sampling")
	_check(course.has_signal("checkpoint_reached"), "Course exposes checkpoint signal")
	_check(course.has_signal("finish_reached"), "Course exposes finish signal")
	var start_transform: Variant = course.call("get_spawn_transform") if course.has_method("get_spawn_transform") else null
	_check(start_transform is Transform3D, "Course start transform is valid")
	var finish := course.find_child("FinishGate", true, false)
	_check(finish != null, "Course contains finish gate")
	var checkpoints := course.find_children("Checkpoint*", "Area3D", true, false)
	_check(checkpoints.size() >= 3, "Course contains recovery checkpoints")
	var jumps := course.find_children("Jump*", "*", true, false)
	_check(jumps.size() >= 4, "Course contains at least three jumps and a large trick jump")
	course.queue_free()
	await process_frame


func _test_weather_contract() -> void:
	var script_path := "res://scripts/weather/weather_manager.gd"
	if not ResourceLoader.exists(script_path):
		_check(false, "Weather manager script exists")
		return
	var manager: Node = (load(script_path) as GDScript).new()
	get_root().add_child(manager)
	await process_frame
	var state_count := 0
	if manager.has_method("get_profile_count"):
		state_count = int(manager.call("get_profile_count"))
	elif manager.has_method("get_state_count"):
		state_count = int(manager.call("get_state_count"))
	elif "profiles" in manager:
		var profiles: Variant = manager.get("profiles")
		state_count = profiles.size() if profiles is Array else 0
	_check(state_count >= 4, "Weather manager provides four weather states")
	var before: Variant = manager.get("target_index")
	if manager.has_method("cycle_weather"):
		manager.call("cycle_weather")
	elif manager.has_method("cycle_state"):
		manager.call("cycle_state")
	var after: Variant = manager.get("target_index")
	_check(before != after, "Weather debug cycle begins a state transition")
	manager.queue_free()
	await process_frame


func _test_external_attribution() -> void:
	var attribution := FileAccess.get_file_as_string("res://ATTRIBUTION.md")
	_check(not attribution.is_empty(), "ATTRIBUTION.md exists")
	var external_root := "res://assets/external"
	for directory: String in DirAccess.get_directories_at(external_root):
		_check(attribution.to_lower().contains(directory.to_lower()), "Attribution covers external asset folder: %s" % directory)
		_check(FileAccess.file_exists("%s/%s/License.txt" % [external_root, directory]), "External asset preserves license: %s" % directory)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS: %s" % label)
	else:
		_failures.append(label)
