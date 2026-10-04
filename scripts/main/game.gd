class_name PowderlineGame
extends Node3D

## Thin composition root. The course, skier, score system, weather, and UI stay
## independently testable and communicate through signals at this boundary.

const COURSE_SCENE_PATH := "res://scenes/courses/mountain_course.tscn"
const SKIER_SCENE_PATH := "res://scenes/player/skier.tscn"
const UI_SCENE_PATH := "res://scenes/ui/game_ui.tscn"

var course: Node3D
var skier: CharacterBody3D
var game_ui: CanvasLayer
var score_manager: Node
var weather_manager: Node
var latest_checkpoint: Transform3D = Transform3D.IDENTITY
var has_checkpoint: bool = false
var active_risk_multiplier: float = 1.0
var _finished: bool = false
var _elapsed: float = 0.0
var _surface_name: StringName = &"packed"
var _weather_drag: float = 1.0
var _active_particles: int = 0


func _ready() -> void:
	_build_world()
	_connect_gameplay()
	_start_run()


func _physics_process(delta: float) -> void:
	if skier == null or _finished:
		return
	_elapsed += delta
	_apply_weather_to_skier()
	_sync_hud_metrics()
	_check_course_bounds()


func _build_world() -> void:
	var course_scene := load(COURSE_SCENE_PATH) as PackedScene
	var skier_scene := load(SKIER_SCENE_PATH) as PackedScene
	var ui_scene := load(UI_SCENE_PATH) as PackedScene
	if course_scene == null or skier_scene == null or ui_scene == null:
		push_error("Powderline could not load one or more required scenes.")
		return

	course = course_scene.instantiate() as Node3D
	add_child(course)
	latest_checkpoint = _course_spawn_transform()
	has_checkpoint = true

	skier = skier_scene.instantiate() as CharacterBody3D
	add_child(skier)
	skier.global_transform = latest_checkpoint
	if skier.has_method("set_checkpoint"):
		skier.call("set_checkpoint", latest_checkpoint)
	score_manager = skier.get_node_or_null("ScoreManager")

	game_ui = ui_scene.instantiate() as CanvasLayer
	add_child(game_ui)
	weather_manager = course.get_node_or_null("WeatherManager")
	if weather_manager == null:
		weather_manager = course.find_child("WeatherManager", true, false)
	if weather_manager != null and weather_manager.has_method("set_follow_target"):
		weather_manager.call("set_follow_target", skier)
	if course.has_method("set_player"):
		course.call("set_player", skier)


func _connect_gameplay() -> void:
	if course == null or skier == null:
		return
	_connect_if_present(course, &"checkpoint_reached", _on_checkpoint_reached)
	_connect_if_present(course, &"finish_reached", _on_finish_reached)
	_connect_if_present(course, &"risk_zone_changed", _on_risk_zone_changed)
	_connect_if_present(course, &"near_miss", _on_near_miss)
	_connect_if_present(course, &"gate_missed", _on_gate_missed)
	_connect_if_present(skier, &"state_changed", _on_skier_state_changed)
	_connect_if_present(skier, &"speed_changed", _on_speed_changed)
	_connect_if_present(skier, &"surface_changed", _on_surface_changed)
	_connect_if_present(skier, &"takeoff", _on_takeoff)
	_connect_if_present(skier, &"landed", _on_landed)
	_connect_if_present(skier, &"crashed", _on_crashed)
	_connect_if_present(skier, &"recovered", _on_recovered)
	_connect_if_present(skier, &"snow_spray_requested", _on_snow_spray_requested)
	_connect_if_present(skier, &"landing_impact", _on_landing_impact)
	if score_manager != null:
		_connect_if_present(score_manager, &"score_changed", _on_score_changed)
		_connect_if_present(score_manager, &"provisional_changed", _on_provisional_changed)
		_connect_if_present(score_manager, &"combo_changed", _on_combo_changed)
		_connect_if_present(score_manager, &"feedback", _on_score_feedback)
	if weather_manager != null:
		_connect_if_present(weather_manager, &"weather_changed", _on_weather_changed)
		_connect_if_present(weather_manager, &"weather_blend_updated", _on_weather_blend_updated)
	_connect_if_present(GameState, &"restart_requested", _on_restart_requested)
	_connect_if_present(SaveManager, &"setting_changed", _on_setting_changed)
	var trick_node := skier.get_node_or_null("TrickController")
	if trick_node != null:
		_connect_if_present(trick_node, &"trick_milestone", _on_trick_milestone)
	_apply_camera_accessibility()
	if weather_manager != null and weather_manager.has_method("get_weather_name"):
		_on_weather_changed(weather_manager.call("get_weather_name") as StringName, int(weather_manager.get("current_index")))


func _start_run() -> void:
	_finished = false
	_elapsed = 0.0
	active_risk_multiplier = 1.0
	if score_manager != null and score_manager.has_method("begin_run"):
		score_manager.call("begin_run")
	if GameState.has_method("start_run"):
		GameState.call("start_run")
	if GameState.has_method("set_checkpoint"):
		GameState.call("set_checkpoint", 0, latest_checkpoint, "START GATE")


func _restart_from_checkpoint(full_run: bool) -> void:
	if skier == null:
		return
	_finished = false
	if full_run:
		latest_checkpoint = _course_spawn_transform()
		has_checkpoint = true
		if skier.has_method("reset_run"):
			skier.call("reset_run", latest_checkpoint)
		_start_run()
	else:
		if skier.has_method("restart_from_checkpoint"):
			skier.call("restart_from_checkpoint")
		else:
			skier.global_transform = latest_checkpoint
			skier.velocity = Vector3.ZERO
	_show_event("CHECKPOINT RESTART", Color("8eeeff"), -100)


func _course_spawn_transform() -> Transform3D:
	if course != null and course.has_method("get_spawn_transform"):
		var value: Variant = course.call("get_spawn_transform")
		if value is Transform3D:
			return value as Transform3D
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 90.0, 0.0))


func _apply_weather_to_skier() -> void:
	if weather_manager == null or skier == null:
		return
	var force := Vector3.ZERO
	var drag_mult := _weather_drag
	if weather_manager.has_method("get_gameplay_modifiers"):
		var modifiers: Dictionary = weather_manager.call("get_gameplay_modifiers")
		force = modifiers.get("airborne_force", Vector3.ZERO) as Vector3
		drag_mult = float(modifiers.get("drag_multiplier", drag_mult))
	if skier.has_method("apply_weather_force"):
		skier.call("apply_weather_force", force, drag_mult)


func _sync_hud_metrics() -> void:
	if skier == null or not GameState.has_method("update_player_metrics"):
		return
	var skier_state_name: StringName = &"GROUNDED"
	if skier.has_method("get_state_name"):
		skier_state_name = skier.call("get_state_name") as StringName
	elif "state" in skier:
		skier_state_name = _state_name(int(skier.get("state")))
	var normal := Vector3.UP
	var probe := skier.get_node_or_null("GroundProbes")
	if probe == null:
		probe = skier.find_child("GroundProbes", true, false)
	if probe != null and "ground_normal" in probe:
		normal = probe.get("ground_normal") as Vector3
	GameState.call(
		"update_player_metrics",
		skier.velocity.length(), skier_state_name, normal, _surface_name, _active_particles
	)
	if AudioManager.has_method("update_ski_audio"):
		var carve := float(skier.get("carve_amount")) if "carve_amount" in skier else 0.0
		var brake := float(skier.get("brake_input")) if "brake_input" in skier else 0.0
		AudioManager.call("update_ski_audio", skier.velocity.length(), _surface_name, carve, brake, not skier.is_on_floor())


func _check_course_bounds() -> void:
	if skier.global_position.y < -25.0 or absf(skier.global_position.x) > 125.0:
		_show_event("OUT OF BOUNDS  -250", Color("ff8b79"), -250)
		if score_manager != null and score_manager.has_method("register_gate_missed"):
			score_manager.call("register_gate_missed")
		_restart_from_checkpoint(false)


func _cycle_weather() -> void:
	if weather_manager == null:
		return
	if weather_manager.has_method("cycle_weather"):
		weather_manager.call("cycle_weather")
	elif weather_manager.has_method("cycle_state"):
		weather_manager.call("cycle_state")


func _on_checkpoint_reached(id: Variant, checkpoint_transform: Transform3D) -> void:
	latest_checkpoint = checkpoint_transform
	has_checkpoint = true
	if skier != null and skier.has_method("set_checkpoint"):
		skier.call("set_checkpoint", checkpoint_transform)
	if GameState.has_method("set_checkpoint"):
		var next_index := int(id) if id is int else int(GameState.get("checkpoint_index")) + 1
		GameState.call("set_checkpoint", next_index, checkpoint_transform, "CHECKPOINT %s" % str(id))
	_show_event("CHECKPOINT  %s" % str(id), Color("79e8ff"), 250)
	_play_audio(&"checkpoint")


func _on_finish_reached() -> void:
	if _finished:
		return
	_finished = true
	if skier != null and skier.has_method("finish_run"):
		skier.call("finish_run")
	var summary: Dictionary = {}
	if score_manager != null and score_manager.has_method("finish_run"):
		var result: Variant = score_manager.call("finish_run")
		if result is Dictionary:
			summary = result as Dictionary
		elif result is int:
			summary["score"] = int(result)
	var final_score := int(summary.get("score", _score_value()))
	if GameState.has_method("finish_run"):
		GameState.call("finish_run", final_score, _elapsed)
	_play_audio(&"finish")


func _on_risk_zone_changed(id: Variant, entered: bool, multiplier: float) -> void:
	active_risk_multiplier = multiplier if entered else 1.0
	if skier != null and skier.has_method("set_external_risk_multiplier"):
		skier.call("set_external_risk_multiplier", active_risk_multiplier)
	if score_manager != null and score_manager.has_method("set_risk_context"):
		score_manager.call("set_risk_context", active_risk_multiplier, 1.0)
	if entered:
		_show_event("RISK LINE  x%.2f" % multiplier, Color("ffcf5a"), 0)


func _on_near_miss(label: Variant = "OBSTACLE", distance: float = 1.0) -> void:
	if score_manager != null and score_manager.has_method("register_near_miss"):
		var current_speed := skier.velocity.length() if skier != null else 10.0
		score_manager.call("register_near_miss", distance, current_speed, StringName(str(label)))
	_show_event("NEAR MISS  %s" % str(label), Color("ffc361"), 350)
	_play_audio(&"near_miss")


func _on_gate_missed(label: Variant = "GATE") -> void:
	if score_manager != null and score_manager.has_method("register_gate_missed"):
		score_manager.call("register_gate_missed")
	_show_event("MISSED %s" % str(label), Color("ff806f"), -200)


func _on_skier_state_changed(_previous: int, current: int) -> void:
	if GameState.has_method("set_player_state"):
		GameState.call("set_player_state", _state_name(current))


func _on_speed_changed(_mps: float) -> void:
	pass


func _on_surface_changed(surface: StringName) -> void:
	_surface_name = surface


func _on_takeoff(_normal: Vector3) -> void:
	_play_audio(&"takeoff")


func _on_landed(success: bool, data: Dictionary) -> void:
	if success:
		# ScoreManager owns banking; clear only the mirrored HUD preview here.
		if GameState.has_method("clear_provisional"):
			GameState.call("clear_provisional")
		_play_audio(&"perfect_landing" if bool(data.get("perfect", false)) else &"landing")
	else:
		if GameState.has_method("clear_provisional"):
			GameState.call("clear_provisional")


func _on_crashed(reason: StringName, impact: float) -> void:
	if GameState.has_method("register_crash"):
		GameState.call("register_crash", str(reason).replace("_", " ").capitalize())
	_play_audio(&"crash", clampf(impact / 24.0, 0.5, 1.4))


func _on_recovered() -> void:
	_show_event("BACK ON YOUR SKIS", Color("9fffd0"), 0)


func _on_snow_spray_requested(kind: StringName, intensity: float, world_position: Vector3, normal: Vector3) -> void:
	if course != null and course.has_method("emit_snow_spray"):
		course.call("emit_snow_spray", kind, intensity, world_position, normal)
	_active_particles = int(roundi(intensity * 90.0))


func _on_landing_impact(intensity: float) -> void:
	if course != null and course.has_method("emit_snow_spray") and skier != null:
		course.call("emit_snow_spray", &"landing", intensity, skier.global_position, Vector3.UP)


func _on_score_changed(score: int, _delta: int = 0) -> void:
	if GameState.has_method("award_points"):
		var current_score := int(GameState.get("banked_score"))
		GameState.call("award_points", score - current_score, "", false)


func _on_provisional_changed(points: int, trick_name: String) -> void:
	if GameState.has_method("set_provisional_trick"):
		GameState.call("set_provisional_trick", trick_name, points)


func _on_combo_changed(multiplier: float, chain: int = 0) -> void:
	if GameState.has_method("set_combo"):
		GameState.call("set_combo", multiplier, chain)


func _on_score_feedback(text_value: String, points: int = 0, positive: bool = true) -> void:
	var color := Color("9fffd0")
	if not positive or points < 0:
		color = Color("ff8877")
	_show_event(text_value, color, points)
	if positive and points > 0:
		_play_audio(&"score", clampf(float(points) / 500.0, 0.35, 1.1))


func _on_trick_milestone(_label: String, _degrees: int) -> void:
	_play_audio(&"trick_milestone", 0.8)


func _on_weather_changed(state: StringName, _state_index: int = 0) -> void:
	var weather_id := state
	var weather_label := String(state).replace("_", " ").capitalize()
	var difficulty := 1.0
	if weather_manager != null and weather_manager.has_method("get_gameplay_modifiers"):
		var modifiers: Dictionary = weather_manager.call("get_gameplay_modifiers")
		difficulty = float(modifiers.get("score_multiplier", 1.0))
	if GameState.has_method("set_weather"):
		GameState.call("set_weather", weather_id, weather_label, difficulty)
	if score_manager != null and score_manager.has_method("set_weather_multiplier"):
		score_manager.call("set_weather_multiplier", difficulty)
	_show_event("WEATHER  //  %s" % weather_label.to_upper(), Color("a9efff"), 0)


func _on_weather_blend_updated(data: Variant) -> void:
	if data is Dictionary:
		var modifiers := data as Dictionary
		_weather_drag = float(modifiers.get("drag_multiplier", 1.0))
		var score_multiplier := float(modifiers.get("score_multiplier", 1.0))
		if score_manager != null and score_manager.has_method("set_weather_multiplier"):
			score_manager.call("set_weather_multiplier", score_multiplier)


func _on_restart_requested(_checkpoint: Transform3D = Transform3D.IDENTITY, _has_checkpoint: bool = true, full_run: bool = false) -> void:
	_restart_from_checkpoint(full_run)


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"reduced_camera_shake":
		_apply_camera_accessibility()


func _apply_camera_accessibility() -> void:
	if skier == null:
		return
	var camera_rig := skier.find_child("CameraRig", true, false)
	if camera_rig != null and camera_rig.has_method("set_reduced_shake"):
		var reduced := bool(SaveManager.call("get_setting", &"reduced_camera_shake", false)) \
			if SaveManager.has_method("get_setting") else false
		camera_rig.call("set_reduced_shake", reduced)


func _score_value() -> int:
	if score_manager != null:
		if "score" in score_manager:
			return int(score_manager.get("score"))
		if "banked_score" in score_manager:
			return int(score_manager.get("banked_score"))
	return 0


func _show_event(message: String, color: Color, points: int) -> void:
	if GameState.has_method("show_event"):
		var tone: StringName = &"info"
		if points < 0 or color.r > 0.9 and color.g < 0.65:
			tone = &"danger"
		elif points > 0:
			tone = &"score"
		elif color.g > 0.75:
			tone = &"success"
		GameState.call("show_event", message, tone, 2.2)


func _state_name(state: int) -> StringName:
	const STATE_NAMES: Array[StringName] = [
		&"GROUNDED", &"AIRBORNE", &"LANDING", &"CRASHED", &"RECOVERING", &"FINISHED"
	]
	return STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else &"GROUNDED"


func _connect_if_present(source: Object, signal_name: StringName, method: Callable) -> void:
	if source.has_signal(signal_name) and not source.is_connected(signal_name, method):
		source.connect(signal_name, method)


func _play_audio(cue: StringName, intensity: float = 1.0) -> void:
	if AudioManager.has_method("play_cue"):
		AudioManager.call("play_cue", cue, intensity)
