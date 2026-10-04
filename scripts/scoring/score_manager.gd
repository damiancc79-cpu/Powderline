class_name ScoreManager
extends Node

## Owns all score banking. TrickController only describes what was attempted;
## provisional trick/airtime points are committed here after a valid landing.

signal score_changed(score: int)
signal provisional_changed(points: int, trick_name: String)
signal combo_changed(multiplier: float, chain_count: int)
signal feedback(message: String, amount: int, positive: bool)
signal run_finished(final_score: int, elapsed_seconds: float)

@export var combo_manager: ComboManager
@export_range(0.0, 100.0, 1.0) var spin_points_per_180: float = 120.0
@export_range(0.0, 1000.0, 5.0) var flip_points: float = 420.0
@export_range(0.0, 1000.0, 5.0) var grab_points: float = 180.0
@export_range(0.0, 500.0, 5.0) var tweak_points: float = 85.0
@export_range(0.0, 1000.0, 5.0) var combined_trick_bonus: float = 260.0
@export_range(0.0, 100.0, 1.0) var airtime_points_per_second: float = 70.0
@export_range(0.0, 1000.0, 5.0) var near_miss_base_points: float = 135.0
@export_range(0.0, 1000.0, 5.0) var crash_bank_penalty: float = 125.0
@export_range(0.0, 1000.0, 5.0) var missed_gate_penalty: float = 100.0
@export_range(0.0, 100.0, 1.0) var clean_run_bonus_per_second: float = 4.0

var score: int = 0
var provisional_points: int = 0
var provisional_name: String = ""
var crash_count: int = 0
var elapsed_seconds: float = 0.0
var weather_multiplier: float = 1.0
var risk_multiplier: float = 1.0
var powder_multiplier: float = 1.0
var run_active: bool = false

var _passive_accumulator: float = 0.0
var _feedback_accumulator: float = 0.0
var _near_miss_cooldowns: Dictionary = {}


func _ready() -> void:
	if combo_manager == null:
		combo_manager = get_node_or_null("ComboManager") as ComboManager
	if combo_manager != null:
		combo_manager.combo_changed.connect(_on_combo_changed)


func begin_run(initial_weather_multiplier: float = 1.0) -> void:
	score = 0
	provisional_points = 0
	provisional_name = ""
	crash_count = 0
	elapsed_seconds = 0.0
	weather_multiplier = maxf(1.0, initial_weather_multiplier)
	risk_multiplier = 1.0
	powder_multiplier = 1.0
	run_active = true
	_passive_accumulator = 0.0
	_feedback_accumulator = 0.0
	_near_miss_cooldowns.clear()
	if combo_manager != null:
		combo_manager.break_combo(&"new_run")
	score_changed.emit(score)
	provisional_changed.emit(0, "")


func physics_tick(
		delta: float,
		speed_mps: float,
		carve_amount: float,
		brake_amount: float,
		surface_key: StringName = &"packed",
		untouched_powder_factor: float = 0.0
	) -> void:
	if not run_active:
		return
	elapsed_seconds += delta
	if combo_manager != null:
		combo_manager.tick(delta)
	for cooldown_key: Variant in _near_miss_cooldowns.keys():
		_near_miss_cooldowns[cooldown_key] = maxf(0.0, float(_near_miss_cooldowns[cooldown_key]) - delta)

	var speed_reward := maxf(0.0, speed_mps - 8.0) * 0.28
	var carve_reward := clampf(carve_amount, 0.0, 1.0) * minf(speed_mps, 32.0) * 0.28
	var braking_penalty := clampf(brake_amount, 0.0, 1.0) * maxf(speed_mps - 5.0, 0.0) * 0.20
	powder_multiplier = lerpf(1.0, 1.18, clampf(untouched_powder_factor, 0.0, 1.0))
	_passive_accumulator += (speed_reward + carve_reward - braking_penalty) \
		* delta * weather_multiplier * risk_multiplier * powder_multiplier
	_feedback_accumulator += delta
	if absf(_passive_accumulator) >= 1.0:
		var whole_points := int(_passive_accumulator)
		_passive_accumulator -= float(whole_points)
		_add_banked_points(whole_points, "", false)
	if String(surface_key).to_lower().contains("ice") and speed_mps > 20.0:
		# Ice risk is intentionally modest but continuous at high speed.
		_passive_accumulator += 0.75 * delta * risk_multiplier


func preview_trick(snapshot: Dictionary) -> int:
	if snapshot.is_empty() or not bool(snapshot.get("has_trick", false)):
		provisional_points = 0
		provisional_name = ""
	else:
		provisional_name = String(snapshot.get("display_name", "Air"))
		var base_points := calculate_trick_points(snapshot)
		var repeat_factor := 1.0
		if combo_manager != null:
			repeat_factor = combo_manager.preview_repeat_factor(StringName(snapshot.get("trick_key", provisional_name)))
		provisional_points = roundi(base_points * repeat_factor * weather_multiplier * risk_multiplier)
	provisional_changed.emit(provisional_points, provisional_name)
	return provisional_points


func calculate_trick_points(snapshot: Dictionary) -> int:
	var spin_steps := int(floor(float(snapshot.get("spin_degrees", 0.0)) / 180.0 + 0.15))
	var flip_count := int(floor(float(snapshot.get("flip_degrees", 0.0)) / 360.0 + 0.15))
	var did_grab := bool(snapshot.get("did_grab", false))
	var tweak_count := int(snapshot.get("tweak_count", 0))
	var component_count := int(spin_steps > 0) + int(flip_count > 0) + int(did_grab)
	var points := float(spin_steps) * spin_points_per_180
	points += float(flip_count) * flip_points
	points += grab_points if did_grab else 0.0
	points += float(tweak_count) * tweak_points
	points += maxf(0.0, float(snapshot.get("airtime", 0.0))) * airtime_points_per_second
	if component_count >= 2:
		points += combined_trick_bonus * float(component_count - 1)
	return maxi(0, roundi(points))


func resolve_landing(snapshot: Dictionary, landing: Dictionary) -> int:
	if not bool(landing.get("success", false)):
		discard_provisional(StringName(landing.get("reason", &"failed_landing")))
		return 0
	if snapshot.is_empty() or not bool(snapshot.get("has_trick", false)):
		discard_provisional(&"no_trick")
		var airtime := maxf(0.0, float(snapshot.get("airtime", 0.0)))
		var air_points := roundi(airtime * airtime_points_per_second \
			* float(landing.get("multiplier", 1.0)) * weather_multiplier * risk_multiplier)
		if airtime >= 0.35:
			_add_banked_points(air_points, "Clean air", true)
		if bool(landing.get("perfect", false)):
			_add_banked_points(50, "Perfect landing", true)
		return air_points

	var event_key := StringName(snapshot.get("trick_key", "air"))
	var combo_data := {"multiplier": 1.0, "repeat_factor": 1.0, "is_duplicate": false}
	if combo_manager != null:
		combo_data = combo_manager.commit_event(event_key)
	var base_points := calculate_trick_points(snapshot)
	var total_multiplier := float(landing.get("multiplier", 1.0)) \
		* float(combo_data.get("multiplier", 1.0)) \
		* float(combo_data.get("repeat_factor", 1.0)) \
		* weather_multiplier * risk_multiplier
	var banked := maxi(0, roundi(float(base_points) * total_multiplier))
	var label := String(snapshot.get("display_name", "Trick"))
	if bool(combo_data.get("is_duplicate", false)):
		label += " (repeat reduced)"
	elif bool(landing.get("perfect", false)):
		label += " · perfect landing"
	_add_banked_points(banked, label, true)
	provisional_points = 0
	provisional_name = ""
	provisional_changed.emit(0, "")
	return banked


func discard_provisional(reason: StringName = &"discarded") -> void:
	if provisional_points > 0:
		feedback.emit("Unbanked trick lost: %s" % String(reason).replace("_", " "), -provisional_points, false)
	provisional_points = 0
	provisional_name = ""
	provisional_changed.emit(0, "")


func register_near_miss(
		distance_metres: float,
		speed_mps: float,
		hazard_key: StringName = &"hazard"
	) -> int:
	if float(_near_miss_cooldowns.get(hazard_key, 0.0)) > 0.0:
		return 0
	if distance_metres > 2.4 or speed_mps < 8.0:
		return 0
	var proximity := 1.0 - clampf(distance_metres / 2.4, 0.0, 1.0)
	var speed_factor := lerpf(0.8, 2.0, clampf((speed_mps - 8.0) / 25.0, 0.0, 1.0))
	var combo_mult := 1.0
	if combo_manager != null:
		var combo_data := combo_manager.commit_event(&"near_miss")
		combo_mult = float(combo_data.get("multiplier", 1.0))
	var points := roundi(near_miss_base_points * (0.6 + proximity) * speed_factor \
		* weather_multiplier * risk_multiplier * combo_mult)
	_near_miss_cooldowns[hazard_key] = 1.2
	_add_banked_points(points, "Near miss", true)
	return points


func set_weather_multiplier(value: float) -> void:
	weather_multiplier = clampf(value, 1.0, 3.0)


func set_risk_context(new_risk_multiplier: float, untouched_powder_bonus: float = 1.0) -> void:
	risk_multiplier = clampf(new_risk_multiplier, 1.0, 4.0)
	powder_multiplier = clampf(untouched_powder_bonus, 1.0, 2.0)


func register_shortcut(shortcut_name: String, base_points: int = 250, route_multiplier: float = 1.35) -> int:
	var points := roundi(float(base_points) * weather_multiplier * maxf(route_multiplier, risk_multiplier))
	_add_banked_points(points, "Shortcut: %s" % shortcut_name, true)
	return points


func register_gate_missed(gate_name: String = "gate") -> void:
	var penalty := mini(score, roundi(missed_gate_penalty))
	_add_banked_points(-penalty, "Missed %s" % gate_name, true)


func register_crash(reason: StringName = &"crash") -> void:
	crash_count += 1
	discard_provisional(reason)
	var penalty := mini(score, roundi(crash_bank_penalty))
	_add_banked_points(-penalty, "Crash", true)
	if combo_manager != null:
		combo_manager.break_combo(&"crash")


func finish_run() -> int:
	if not run_active:
		return score
	if crash_count == 0:
		var clean_bonus := roundi(minf(1000.0, elapsed_seconds * clean_run_bonus_per_second))
		_add_banked_points(clean_bonus, "Clean run", true)
	run_active = false
	discard_provisional(&"finish")
	run_finished.emit(score, elapsed_seconds)
	return score


func _add_banked_points(amount: int, label: String, announce: bool) -> void:
	if amount == 0:
		return
	score = maxi(0, score + amount)
	score_changed.emit(score)
	if announce and not label.is_empty():
		feedback.emit(label, amount, amount >= 0)


func _on_combo_changed(new_multiplier: float, chain_count: int) -> void:
	combo_changed.emit(new_multiplier, chain_count)
