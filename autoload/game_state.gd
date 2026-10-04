extends Node

## Shared, signal-driven run state. Gameplay systems write here; UI systems only read
## the public properties or listen to signals, so neither side needs scene paths.

signal run_started(run_number: int)
signal run_reset
signal run_finished(result: Dictionary)
signal pause_state_changed(is_paused: bool)
signal score_changed(banked_score: int, provisional_score: int, display_score: int)
signal combo_changed(multiplier: float, chain_count: int)
signal trick_changed(trick_name: String, provisional_score: int)
signal metrics_changed(metrics: Dictionary)
signal weather_changed(weather_id: StringName, display_name: String, difficulty_multiplier: float)
signal player_state_changed(state: StringName)
signal checkpoint_reached(index: int, label: String)
signal feedback_requested(message: String, tone: StringName, duration: float)
signal restart_requested(checkpoint_transform: Transform3D, has_checkpoint: bool, full_run: bool)
signal records_changed(best_score: int, best_time_seconds: float)

const DEFAULT_WEATHER_ID: StringName = &"clear"
const DEFAULT_SURFACE_ID: StringName = &"powder"
const DEFAULT_PLAYER_STATE: StringName = &"GROUNDED"

var run_active: bool = false
var run_finished_flag: bool = false
var run_paused: bool = false
var run_number: int = 0
var elapsed_seconds: float = 0.0
var banked_score: int = 0
var provisional_score: int = 0
var combo_multiplier: float = 1.0
var combo_chain: int = 0
var current_trick: String = ""
var crashes: int = 0

var speed_mps: float = 0.0
var surface_id: StringName = DEFAULT_SURFACE_ID
var player_state: StringName = DEFAULT_PLAYER_STATE
var ground_normal: Vector3 = Vector3.UP
var active_particle_count: int = 0
var weather_id: StringName = DEFAULT_WEATHER_ID
var weather_display_name: String = "Clear"
var weather_difficulty_multiplier: float = 1.0

var checkpoint_index: int = -1
var checkpoint_label: String = "Start"
var checkpoint_transform: Transform3D = Transform3D.IDENTITY
var has_checkpoint: bool = false

var best_score: int = 0
var best_time_seconds: float = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_sync_records_from_save_manager")


func _process(delta: float) -> void:
	if run_active and not run_finished_flag and not run_paused:
		elapsed_seconds += delta


func start_run() -> void:
	run_number += 1
	run_active = true
	run_finished_flag = false
	run_paused = false
	elapsed_seconds = 0.0
	banked_score = 0
	provisional_score = 0
	combo_multiplier = 1.0
	combo_chain = 0
	current_trick = ""
	crashes = 0
	speed_mps = 0.0
	player_state = DEFAULT_PLAYER_STATE
	ground_normal = Vector3.UP
	checkpoint_index = -1
	checkpoint_label = "Start"
	checkpoint_transform = Transform3D.IDENTITY
	has_checkpoint = false
	run_started.emit(run_number)
	run_reset.emit()
	_emit_score()
	combo_changed.emit(combo_multiplier, combo_chain)
	trick_changed.emit(current_trick, provisional_score)
	player_state_changed.emit(player_state)


func set_run_paused(value: bool) -> void:
	if run_paused == value:
		return
	run_paused = value
	pause_state_changed.emit(run_paused)


func update_player_metrics(
	new_speed_mps: float,
	new_state: StringName = &"",
	new_ground_normal: Vector3 = Vector3.UP,
	new_surface: StringName = &"",
	new_active_particle_count: int = -1
) -> void:
	speed_mps = maxf(new_speed_mps, 0.0)
	ground_normal = new_ground_normal.normalized() if not new_ground_normal.is_zero_approx() else Vector3.UP
	if not new_state.is_empty() and new_state != player_state:
		player_state = new_state
		player_state_changed.emit(player_state)
	if not new_surface.is_empty():
		surface_id = new_surface
	if new_active_particle_count >= 0:
		active_particle_count = new_active_particle_count
	metrics_changed.emit(get_metrics())


func update_metrics(values: Dictionary) -> void:
	## Dictionary adapter for systems that already collect diagnostics in one payload.
	update_player_metrics(
		float(values.get("speed_mps", speed_mps)),
		StringName(values.get("player_state", player_state)),
		values.get("ground_normal", ground_normal) as Vector3,
		StringName(values.get("surface", surface_id)),
		int(values.get("active_particles", active_particle_count))
	)


func get_metrics() -> Dictionary:
	return {
		"speed_mps": speed_mps,
		"speed_kph": speed_mps * 3.6,
		"player_state": player_state,
		"ground_normal": ground_normal,
		"surface": surface_id,
		"active_particles": active_particle_count,
		"weather": weather_id,
		"elapsed_seconds": elapsed_seconds,
	}


func set_weather(new_id: StringName, display_name: String = "", difficulty_multiplier: float = 1.0) -> void:
	weather_id = new_id
	weather_display_name = display_name if not display_name.is_empty() else _title_case_id(new_id)
	weather_difficulty_multiplier = maxf(difficulty_multiplier, 1.0)
	weather_changed.emit(weather_id, weather_display_name, weather_difficulty_multiplier)


func set_player_state(new_state: StringName) -> void:
	if new_state == player_state:
		return
	player_state = new_state
	player_state_changed.emit(player_state)


func award_points(points: int, reason: String = "", provisional: bool = false) -> void:
	if provisional:
		provisional_score = maxi(provisional_score + points, 0)
	else:
		banked_score = maxi(banked_score + points, 0)
	_emit_score()
	if not reason.is_empty():
		var prefix := "+" if points >= 0 else ""
		show_event("%s%d  %s" % [prefix, points, reason], &"score" if points >= 0 else &"danger")


func set_provisional_trick(trick_name: String, points: int) -> void:
	current_trick = trick_name
	provisional_score = maxi(points, 0)
	trick_changed.emit(current_trick, provisional_score)
	_emit_score()


func bank_provisional(reason: String = "Landed") -> int:
	var banked := provisional_score
	if banked <= 0:
		current_trick = ""
		trick_changed.emit(current_trick, provisional_score)
		return 0
	banked_score += banked
	provisional_score = 0
	current_trick = ""
	_emit_score()
	trick_changed.emit(current_trick, provisional_score)
	show_event("+%d  %s" % [banked, reason], &"success", 2.2)
	return banked


func clear_provisional(reason: String = "") -> int:
	var lost := provisional_score
	provisional_score = 0
	current_trick = ""
	_emit_score()
	trick_changed.emit(current_trick, provisional_score)
	if lost > 0 and not reason.is_empty():
		show_event("-%d  %s" % [lost, reason], &"danger", 2.4)
	return lost


func set_combo(multiplier: float, chain_count: int) -> void:
	combo_multiplier = maxf(multiplier, 1.0)
	combo_chain = maxi(chain_count, 0)
	combo_changed.emit(combo_multiplier, combo_chain)


func register_crash(reason: String = "Wipeout") -> void:
	crashes += 1
	clear_provisional("Combo lost")
	set_combo(1.0, 0)
	set_player_state(&"CRASHED")
	show_event(reason, &"danger", 2.8)


func set_checkpoint(index: int, world_transform: Transform3D, label: String = "Checkpoint") -> void:
	if index < checkpoint_index:
		return
	checkpoint_index = index
	checkpoint_transform = world_transform
	checkpoint_label = label
	has_checkpoint = true
	checkpoint_reached.emit(checkpoint_index, checkpoint_label)
	show_event(checkpoint_label, &"checkpoint", 2.0)


func request_restart(full_run: bool = false) -> void:
	if full_run:
		start_run()
	restart_requested.emit(checkpoint_transform, has_checkpoint, full_run)


func show_event(message: String, tone: StringName = &"info", duration: float = 2.0) -> void:
	if message.is_empty():
		return
	feedback_requested.emit(message, tone, clampf(duration, 0.4, 8.0))


func finish_run(final_score_override: int = -1, final_time_override: float = -1.0) -> Dictionary:
	if run_finished_flag:
		return _build_result(false, false)
	if final_score_override >= 0:
		banked_score = final_score_override
	if final_time_override >= 0.0:
		elapsed_seconds = final_time_override
	bank_provisional("Final landing")
	run_active = false
	run_finished_flag = true
	set_player_state(&"FINISHED")
	var new_best_score := banked_score > best_score
	var new_best_time := best_time_seconds < 0.0 or elapsed_seconds < best_time_seconds
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("submit_run"):
		var record_result: Variant = save_manager.call("submit_run", banked_score, elapsed_seconds)
		if record_result is Dictionary:
			new_best_score = bool(record_result.get("new_best_score", new_best_score))
			new_best_time = bool(record_result.get("new_best_time", new_best_time))
			best_score = int(record_result.get("best_score", maxi(best_score, banked_score)))
			best_time_seconds = float(record_result.get("best_time_seconds", elapsed_seconds if new_best_time else best_time_seconds))
	else:
		best_score = maxi(best_score, banked_score)
		if new_best_time:
			best_time_seconds = elapsed_seconds
	records_changed.emit(best_score, best_time_seconds)
	var result := _build_result(new_best_score, new_best_time)
	run_finished.emit(result)
	return result


func _build_result(new_best_score: bool, new_best_time: bool) -> Dictionary:
	return {
		"score": banked_score,
		"time_seconds": elapsed_seconds,
		"best_score": best_score,
		"best_time_seconds": best_time_seconds,
		"new_best_score": new_best_score,
		"new_best_time": new_best_time,
		"crashes": crashes,
		"weather": weather_display_name,
	}


func _emit_score() -> void:
	score_changed.emit(banked_score, provisional_score, banked_score + provisional_score)


func _sync_records_from_save_manager() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_records"):
		return
	var records: Variant = save_manager.call("get_records")
	if records is Dictionary:
		best_score = int(records.get("best_score", 0))
		best_time_seconds = float(records.get("best_time_seconds", -1.0))
		records_changed.emit(best_score, best_time_seconds)


func _title_case_id(value: StringName) -> String:
	return String(value).replace("_", " ").capitalize()
