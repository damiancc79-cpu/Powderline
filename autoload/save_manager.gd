extends Node

## Versioned ConfigFile persistence with strict validation and an atomic temp-file
## replacement. Bad files never prevent the game from launching.

signal settings_loaded(settings: Dictionary)
signal setting_changed(key: StringName, value: Variant)
signal records_changed(records: Dictionary)
signal save_failed(path: String, error: Error)

const SAVE_PATH := "user://powderline.cfg"
const SAVE_VERSION := 1
const SETTINGS_SECTION := "settings"
const RECORDS_SECTION := "records"

const DEFAULT_SETTINGS := {
	"master_volume": 0.82,
	"sfx_volume": 0.88,
	"ambient_volume": 0.72,
	"controller_deadzone": 0.20,
	"reduced_camera_shake": false,
	"ui_scale": 1.0,
	"show_debug_stats": false,
	"controller_prompts": "auto",
}

var _settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var _records: Dictionary = {
	"best_score": 0,
	"best_time_seconds": -1.0,
	"completed_runs": 0,
	"total_crashes": 0,
}
var _active_path: String = SAVE_PATH


func _ready() -> void:
	load_data()
	_apply_runtime_settings()


func load_data(path: String = SAVE_PATH) -> bool:
	_active_path = path
	_settings = DEFAULT_SETTINGS.duplicate(true)
	_records = {
		"best_score": 0,
		"best_time_seconds": -1.0,
		"completed_runs": 0,
		"total_crashes": 0,
	}
	if not FileAccess.file_exists(path):
		settings_loaded.emit(get_settings())
		records_changed.emit(get_records())
		return true
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		_preserve_malformed_file(path)
		settings_loaded.emit(get_settings())
		records_changed.emit(get_records())
		return false
	_read_validated_settings(config)
	_read_validated_records(config)
	_apply_runtime_settings()
	settings_loaded.emit(get_settings())
	records_changed.emit(get_records())
	return true


func save_data(path: String = "") -> bool:
	var destination := _active_path if path.is_empty() else path
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	for key: String in _settings:
		config.set_value(SETTINGS_SECTION, key, _settings[key])
	for key: String in _records:
		config.set_value(RECORDS_SECTION, key, _records[key])
	var temporary := destination + ".tmp"
	var error := config.save(temporary)
	if error != OK:
		save_failed.emit(destination, error)
		return false
	var source_absolute := ProjectSettings.globalize_path(temporary)
	var destination_absolute := ProjectSettings.globalize_path(destination)
	if FileAccess.file_exists(destination):
		var backup_absolute := destination_absolute + ".bak"
		if FileAccess.file_exists(destination + ".bak"):
			DirAccess.remove_absolute(backup_absolute)
		DirAccess.rename_absolute(destination_absolute, backup_absolute)
	error = DirAccess.rename_absolute(source_absolute, destination_absolute)
	if error != OK:
		var backup_path := destination + ".bak"
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(destination):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), destination_absolute)
		save_failed.emit(destination, error)
		return false
	return true


func reset_to_defaults(save_immediately: bool = true) -> void:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	_apply_runtime_settings()
	settings_loaded.emit(get_settings())
	if save_immediately:
		save_data()


func get_settings() -> Dictionary:
	return _settings.duplicate(true)


func get_setting(key: StringName, fallback: Variant = null) -> Variant:
	return _settings.get(String(key), fallback)


func set_setting(key: StringName, value: Variant, save_immediately: bool = true) -> bool:
	var normalized: Variant = _validate_setting(String(key), value)
	if normalized == null:
		return false
	var string_key := String(key)
	if _settings.get(string_key) == normalized:
		return true
	_settings[string_key] = normalized
	_apply_runtime_setting(string_key, normalized)
	setting_changed.emit(key, normalized)
	if save_immediately:
		save_data()
	return true


func get_records() -> Dictionary:
	return _records.duplicate(true)


func submit_run(score: int, time_seconds: float, crash_count: int = 0) -> Dictionary:
	var valid_score := maxi(score, 0)
	var valid_time := maxf(time_seconds, 0.0)
	var previous_score := int(_records.get("best_score", 0))
	var previous_time := float(_records.get("best_time_seconds", -1.0))
	var new_best_score := valid_score > previous_score
	var new_best_time := valid_time > 0.0 and (previous_time < 0.0 or valid_time < previous_time)
	if new_best_score:
		_records["best_score"] = valid_score
	if new_best_time:
		_records["best_time_seconds"] = valid_time
	_records["completed_runs"] = int(_records.get("completed_runs", 0)) + 1
	_records["total_crashes"] = int(_records.get("total_crashes", 0)) + maxi(crash_count, 0)
	save_data()
	records_changed.emit(get_records())
	return {
		"new_best_score": new_best_score,
		"new_best_time": new_best_time,
		"best_score": int(_records["best_score"]),
		"best_time_seconds": float(_records["best_time_seconds"]),
	}


func _read_validated_settings(config: ConfigFile) -> void:
	for key: String in DEFAULT_SETTINGS:
		if not config.has_section_key(SETTINGS_SECTION, key):
			continue
		var normalized: Variant = _validate_setting(key, config.get_value(SETTINGS_SECTION, key))
		if normalized != null:
			_settings[key] = normalized


func _read_validated_records(config: ConfigFile) -> void:
	_records["best_score"] = _validated_int(config.get_value(RECORDS_SECTION, "best_score", 0), 0, 2_000_000_000, 0)
	_records["best_time_seconds"] = _validated_float(config.get_value(RECORDS_SECTION, "best_time_seconds", -1.0), -1.0, 86_400.0, -1.0)
	_records["completed_runs"] = _validated_int(config.get_value(RECORDS_SECTION, "completed_runs", 0), 0, 2_000_000_000, 0)
	_records["total_crashes"] = _validated_int(config.get_value(RECORDS_SECTION, "total_crashes", 0), 0, 2_000_000_000, 0)


func _validate_setting(key: String, value: Variant) -> Variant:
	match key:
		"master_volume", "sfx_volume", "ambient_volume":
			return _validated_float(value, 0.0, 1.0, float(DEFAULT_SETTINGS[key]))
		"controller_deadzone":
			return _validated_float(value, 0.05, 0.60, float(DEFAULT_SETTINGS[key]))
		"ui_scale":
			return _validated_float(value, 0.80, 1.35, float(DEFAULT_SETTINGS[key]))
		"reduced_camera_shake", "show_debug_stats":
			return value if value is bool else bool(DEFAULT_SETTINGS[key])
		"controller_prompts":
			var prompt_mode := String(value)
			return prompt_mode if prompt_mode in ["auto", "keyboard", "controller"] else String(DEFAULT_SETTINGS[key])
	return null


func _validated_float(value: Variant, minimum: float, maximum: float, fallback: float) -> float:
	if value is float or value is int:
		var number := float(value)
		if is_finite(number):
			return clampf(number, minimum, maximum)
	return fallback


func _validated_int(value: Variant, minimum: int, maximum: int, fallback: int) -> int:
	if value is int or value is float:
		var number := int(value)
		return clampi(number, minimum, maximum)
	return fallback


func _apply_runtime_settings() -> void:
	for key: String in _settings:
		_apply_runtime_setting(key, _settings[key])


func _apply_runtime_setting(key: String, value: Variant) -> void:
	if key == "controller_deadzone":
		for action: StringName in [&"move_forward", &"move_back", &"steer_left", &"steer_right"]:
			if InputMap.has_action(action):
				InputMap.action_set_deadzone(action, float(value))


func _preserve_malformed_file(path: String) -> void:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return
	var bytes := source.get_buffer(source.get_length())
	var timestamp := int(Time.get_unix_time_from_system())
	var backup := FileAccess.open("%s.corrupt-%d" % [path, timestamp], FileAccess.WRITE)
	if backup != null:
		backup.store_buffer(bytes)
