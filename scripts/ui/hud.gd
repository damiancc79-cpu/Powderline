extends Control

const ThemeFactory = preload("res://scripts/ui/powderline_theme.gd")

var _speed_label: Label
var _time_label: Label
var _score_label: Label
var _provisional_label: Label
var _combo_label: Label
var _trick_label: Label
var _trick_score_label: Label
var _weather_label: Label
var _weather_risk_label: Label
var _surface_label: Label
var _toast_panel: PanelContainer
var _toast_label: Label
var _prompt_label: Label
var _debug_panel: PanelContainer
var _debug_label: Label
var _toast_tween: Tween
var _debug_accumulator: float = 0.0
var _latest_metrics: Dictionary = {}
var _using_controller: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	_connect_game_state()
	_connect_settings()
	_refresh_from_state()
	set_process(true)


func _process(delta: float) -> void:
	_debug_accumulator += delta
	if _debug_accumulator < 0.15:
		return
	_debug_accumulator = 0.0
	_update_clock()
	_update_debug_text()


func set_input_device(using_controller: bool) -> void:
	_using_controller = using_controller
	if _prompt_label == null:
		return
	_prompt_label.text = (
		"LS  CARVE / TUCK     A  POP     X + LS / Y + LS  TRICKS     LB  GRAB     START  MENU"
		if _using_controller
		else "WASD  CARVE / TUCK     SPACE  POP     Q + DIRECTION / E + DIRECTION  TRICKS     ESC  MENU"
	)


func set_debug_visible(value: bool) -> void:
	if _debug_panel != null:
		_debug_panel.visible = value


func _build_interface() -> void:
	_build_top_bar()
	_build_trick_readout()
	_build_toast()
	_build_prompt()
	_build_debug_panel()


func _build_top_bar() -> void:
	var safe_area := MarginContainer.new()
	safe_area.name = "TopSafeArea"
	safe_area.set_anchors_preset(Control.PRESET_TOP_WIDE)
	safe_area.offset_bottom = 132.0
	safe_area.add_theme_constant_override("margin_left", 26)
	safe_area.add_theme_constant_override("margin_top", 24)
	safe_area.add_theme_constant_override("margin_right", 26)
	add_child(safe_area)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	safe_area.add_child(row)

	var movement_panel := PanelContainer.new()
	movement_panel.custom_minimum_size = Vector2(226, 104)
	movement_panel.theme_type_variation = &"GlassPanel"
	row.add_child(movement_panel)
	var movement := VBoxContainer.new()
	movement.add_theme_constant_override("separation", -2)
	movement_panel.add_child(movement)
	movement.add_child(_make_label("SPEED", &"EyebrowLabel"))
	_speed_label = _make_label("0 km/h", &"MetricLabel")
	movement.add_child(_speed_label)
	_time_label = _make_label("00:00.0", &"MutedLabel")
	movement.add_child(_time_label)

	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_left)

	var conditions := VBoxContainer.new()
	conditions.alignment = BoxContainer.ALIGNMENT_CENTER
	conditions.custom_minimum_size = Vector2(290, 96)
	conditions.add_theme_constant_override("separation", 7)
	row.add_child(conditions)
	var weather_chip := _make_chip("WEATHER")
	_weather_label = weather_chip.get_node("Row/Value") as Label
	conditions.add_child(weather_chip)
	var surface_chip := _make_chip("SURFACE")
	_surface_label = surface_chip.get_node("Row/Value") as Label
	conditions.add_child(surface_chip)
	_weather_risk_label = _make_label("", &"GoldLabel")
	_weather_risk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weather_risk_label.visible = false
	conditions.add_child(_weather_risk_label)

	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_right)

	var score_panel := PanelContainer.new()
	score_panel.custom_minimum_size = Vector2(250, 104)
	score_panel.theme_type_variation = &"GlassPanel"
	row.add_child(score_panel)
	var scoring := VBoxContainer.new()
	scoring.add_theme_constant_override("separation", -2)
	score_panel.add_child(scoring)
	var score_title_row := HBoxContainer.new()
	score_title_row.add_child(_make_label("SCORE", &"EyebrowLabel"))
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_title_row.add_child(title_spacer)
	_combo_label = _make_label("x1.0", &"GoldLabel")
	score_title_row.add_child(_combo_label)
	scoring.add_child(score_title_row)
	_score_label = _make_label("0", &"MetricLabel")
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scoring.add_child(_score_label)
	_provisional_label = _make_label("", &"AccentLabel")
	_provisional_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scoring.add_child(_provisional_label)


func _build_trick_readout() -> void:
	var trick_panel := PanelContainer.new()
	trick_panel.name = "TrickReadout"
	trick_panel.theme_type_variation = &"GlassPanel"
	trick_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	trick_panel.offset_left = -230.0
	trick_panel.offset_top = 155.0
	trick_panel.offset_right = 230.0
	trick_panel.offset_bottom = 235.0
	trick_panel.modulate.a = 0.0
	add_child(trick_panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	trick_panel.add_child(row)
	_trick_label = _make_label("", &"MetricLabel")
	_trick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_trick_label)
	_trick_score_label = _make_label("", &"GoldLabel")
	row.add_child(_trick_score_label)


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "FeedbackToast"
	_toast_panel.theme_type_variation = &"ToastPanel"
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER)
	_toast_panel.offset_left = -270.0
	_toast_panel.offset_top = 72.0
	_toast_panel.offset_right = 270.0
	_toast_panel.offset_bottom = 126.0
	_toast_panel.modulate.a = 0.0
	add_child(_toast_panel)
	_toast_label = _make_label("", &"AccentLabel")
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_label)


func _build_prompt() -> void:
	var prompt_panel := PanelContainer.new()
	prompt_panel.name = "ControlPrompt"
	prompt_panel.theme_type_variation = &"Chip"
	prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_panel.offset_left = -440.0
	prompt_panel.offset_top = -64.0
	prompt_panel.offset_right = 440.0
	prompt_panel.offset_bottom = -22.0
	add_child(prompt_panel)
	_prompt_label = _make_label("", &"MutedLabel")
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel.add_child(_prompt_label)
	set_input_device(false)


func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.name = "DebugStats"
	_debug_panel.theme_type_variation = &"GlassPanel"
	_debug_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_debug_panel.offset_left = 24.0
	_debug_panel.offset_top = -182.0
	_debug_panel.offset_right = 314.0
	_debug_panel.offset_bottom = -24.0
	_debug_panel.visible = false
	add_child(_debug_panel)
	_debug_label = _make_label("", &"DebugLabel")
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_debug_panel.add_child(_debug_label)


func _make_chip(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Chip"
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var title_label := _make_label(title, &"EyebrowLabel")
	row.add_child(title_label)
	var value_label := _make_label("--", &"AccentLabel")
	value_label.name = "Value"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return panel


func _make_label(text_value: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text_value
	if not variation.is_empty():
		label.theme_type_variation = variation
	return label


func _connect_game_state() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	state.connect("score_changed", Callable(self, "_on_score_changed"))
	state.connect("combo_changed", Callable(self, "_on_combo_changed"))
	state.connect("trick_changed", Callable(self, "_on_trick_changed"))
	state.connect("metrics_changed", Callable(self, "_on_metrics_changed"))
	state.connect("weather_changed", Callable(self, "_on_weather_changed"))
	state.connect("feedback_requested", Callable(self, "_on_feedback_requested"))
	state.connect("checkpoint_reached", Callable(self, "_on_checkpoint_reached"))


func _connect_settings() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null:
		return
	if save_manager.has_method("get_setting"):
		set_debug_visible(bool(save_manager.call("get_setting", &"show_debug_stats", false)))
	if save_manager.has_signal("setting_changed"):
		save_manager.connect("setting_changed", Callable(self, "_on_setting_changed"))


func _refresh_from_state() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	_on_score_changed(int(state.get("banked_score")), int(state.get("provisional_score")), int(state.get("banked_score")) + int(state.get("provisional_score")))
	_on_combo_changed(float(state.get("combo_multiplier")), int(state.get("combo_chain")))
	_on_trick_changed(String(state.get("current_trick")), int(state.get("provisional_score")))
	_on_metrics_changed(state.call("get_metrics"))
	_on_weather_changed(StringName(state.get("weather_id")), String(state.get("weather_display_name")), float(state.get("weather_difficulty_multiplier")))


func _on_score_changed(banked: int, provisional: int, _displayed: int) -> void:
	_score_label.text = _group_number(banked)
	_provisional_label.text = "+%s provisional" % _group_number(provisional) if provisional > 0 else ""


func _on_combo_changed(multiplier: float, chain_count: int) -> void:
	_combo_label.text = "x%.1f" % multiplier
	_combo_label.tooltip_text = "%d linked actions" % chain_count


func _on_trick_changed(trick_name: String, points: int) -> void:
	_trick_label.text = trick_name.to_upper()
	_trick_score_label.text = "+%s" % _group_number(points) if points > 0 else ""
	var panel := _trick_label.get_parent().get_parent() as PanelContainer
	var should_show := not trick_name.is_empty() or points > 0
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(panel, "modulate:a", 1.0 if should_show else 0.0, 0.16)


func _on_metrics_changed(metrics: Dictionary) -> void:
	_latest_metrics = metrics
	_speed_label.text = "%d km/h" % roundi(float(metrics.get("speed_kph", 0.0)))
	_surface_label.text = String(metrics.get("surface", &"powder")).replace("_", " ").to_upper()


func _on_weather_changed(_id: StringName, display_name: String, risk_multiplier: float) -> void:
	_weather_label.text = display_name.to_upper()
	_weather_risk_label.text = "RISK  x%.2f" % risk_multiplier
	_weather_risk_label.visible = risk_multiplier > 1.01


func _on_feedback_requested(message: String, tone: StringName, duration: float) -> void:
	_toast_label.text = message
	match tone:
		&"danger":
			_toast_label.theme_type_variation = &"DangerLabel"
		&"success", &"checkpoint":
			_toast_label.theme_type_variation = &"GoldLabel"
		_:
			_toast_label.theme_type_variation = &"AccentLabel"
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_panel.modulate.a = 0.0
	_toast_panel.position.y += 7.0
	_toast_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.16)
	_toast_tween.tween_property(_toast_panel, "position:y", _toast_panel.position.y - 7.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_toast_tween.chain().set_parallel(false)
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.25)


func _on_checkpoint_reached(_index: int, label: String) -> void:
	_on_feedback_requested("CHECKPOINT  /  %s" % label.to_upper(), &"checkpoint", 2.0)


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"show_debug_stats":
		set_debug_visible(bool(value))


func _update_clock() -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null:
		_time_label.text = _format_time(float(state.get("elapsed_seconds")))


func _update_debug_text() -> void:
	if not _debug_panel.visible:
		return
	var normal: Vector3 = _latest_metrics.get("ground_normal", Vector3.UP)
	_debug_label.text = (
		"PERFORMANCE  %d FPS\n"
		+ "SPEED        %5.1f m/s\n"
		+ "STATE        %s\n"
		+ "GROUND       %.2f, %.2f, %.2f\n"
		+ "SURFACE      %s\n"
		+ "PARTICLES    %d"
	) % [
		Engine.get_frames_per_second(),
		float(_latest_metrics.get("speed_mps", 0.0)),
		String(_latest_metrics.get("player_state", &"--")),
		normal.x,
		normal.y,
		normal.z,
		String(_latest_metrics.get("surface", &"--")),
		int(_latest_metrics.get("active_particles", 0)),
	]


func _format_time(seconds: float) -> String:
	var safe_seconds := maxf(seconds, 0.0)
	var minutes := int(safe_seconds) / 60
	var remainder := fmod(safe_seconds, 60.0)
	return "%02d:%04.1f" % [minutes, remainder]


func _group_number(value: int) -> String:
	var source := str(maxi(value, 0))
	var grouped := ""
	for index: int in range(source.length()):
		if index > 0 and (source.length() - index) % 3 == 0:
			grouped += ","
		grouped += source[index]
	return grouped
