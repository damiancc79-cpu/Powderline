class_name ComboManager
extends Node

## Tracks a short risk/trick chain and applies duplicate-trick decay. It does not
## own the actual score, which keeps banking policy in ScoreManager.

signal combo_changed(multiplier: float, chain_count: int)
signal combo_broken(reason: StringName)

@export_range(0.5, 20.0, 0.1) var combo_window_seconds: float = 5.5
@export_range(0.0, 2.0, 0.05) var multiplier_step: float = 0.25
@export_range(1.0, 10.0, 0.25) var maximum_multiplier: float = 5.0
@export_range(0.05, 1.0, 0.05) var repeated_trick_factor: float = 0.55
@export_range(1, 12, 1) var recent_history_size: int = 6

var chain_count: int = 0
var multiplier: float = 1.0
var time_remaining: float = 0.0
var recent_events: Array[StringName] = []


func tick(delta: float) -> void:
	if chain_count <= 0:
		return
	time_remaining = maxf(0.0, time_remaining - delta)
	if time_remaining <= 0.0:
		break_combo(&"expired")


func preview_repeat_factor(event_key: StringName) -> float:
	var repeats := 0
	for previous_key: StringName in recent_events:
		if previous_key == event_key:
			repeats += 1
	return pow(repeated_trick_factor, repeats)


func commit_event(event_key: StringName, extends_combo: bool = true) -> Dictionary:
	var repeat_factor := preview_repeat_factor(event_key)
	if extends_combo:
		chain_count += 1
		time_remaining = combo_window_seconds
		multiplier = minf(maximum_multiplier, 1.0 + float(maxi(0, chain_count - 1)) * multiplier_step)
	else:
		chain_count = maxi(chain_count, 1)
		time_remaining = maxf(time_remaining, combo_window_seconds * 0.5)
	recent_events.push_front(event_key)
	while recent_events.size() > recent_history_size:
		recent_events.pop_back()
	combo_changed.emit(multiplier, chain_count)
	return {
		"multiplier": multiplier,
		"chain_count": chain_count,
		"repeat_factor": repeat_factor,
		"is_duplicate": repeat_factor < 0.99,
	}


func break_combo(reason: StringName = &"reset") -> void:
	var had_combo := chain_count > 0
	chain_count = 0
	multiplier = 1.0
	time_remaining = 0.0
	recent_events.clear()
	combo_changed.emit(multiplier, chain_count)
	if had_combo:
		combo_broken.emit(reason)


func snapshot() -> Dictionary:
	return {
		"chain_count": chain_count,
		"multiplier": multiplier,
		"time_remaining": time_remaining,
		"recent_events": recent_events.duplicate(),
	}
