extends Control

signal back_requested

var _back_button: Button
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _reduced_shake: CheckButton
var _debug_stats: CheckButton
var _prompt_mode: OptionButton
var _footer_label: Label
var _save_timer: Timer
var _loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	_load_settings()
	visible = false


func show_panel(using_controller: bool = false) -> void:
	_load_settings()
	set_input_device(using_controller)
	visible = true
	_back_button.grab_focus()


func hide_panel() -> void:
	_flush_save()
	visible = false


func set_input_device(using_controller: bool) -> void:
	if _footer_label != null:
		_footer_label.text = "B  BACK     DPAD / STICK  ADJUST" if using_controller else "ESC  BACK     ARROWS  ADJUST"


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.025, 0.04, 0.90)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var card := PanelContainer.new()
	card.theme_type_variation = &"GlassPanel"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -355.0
	card.offset_top = -330.0
	card.offset_right = 355.0
	card.offset_bottom = 330.0
	add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	card.add_child(content)

	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(titles)
	var eyebrow := Label.new()
	eyebrow.text = "ACCESSIBILITY + FEEL"
	eyebrow.theme_type_variation = &"EyebrowLabel"
	titles.add_child(eyebrow)
	var title := Label.new()
	title.text = "SETTINGS"
	title.theme_type_variation = &"HeroLabel"
	titles.add_child(title)
	_back_button = Button.new()
	_back_button.text = "BACK"
	_back_button.theme_type_variation = &"GhostButton"
	_back_button.custom_minimum_size = Vector2(126, 48)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	title_row.add_child(_back_button)

	_add_slider_setting(content, "MASTER VOLUME", "All procedural and impact audio", &"master_volume", 0.0, 1.0, 0.01)
	_add_slider_setting(content, "EFFECTS VOLUME", "Jumps, tricks, landings and score cues", &"sfx_volume", 0.0, 1.0, 0.01)
	_add_slider_setting(content, "SNOW + WIND VOLUME", "Speed-reactive ski and weather bed", &"ambient_volume", 0.0, 1.0, 0.01)
	_add_slider_setting(content, "CONTROLLER DEAD ZONE", "Applied to steering and forward/back actions", &"controller_deadzone", 0.05, 0.60, 0.01)
	_add_slider_setting(content, "UI SCALE", "Scales all text and focus targets", &"ui_scale", 0.80, 1.35, 0.05)

	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 18)
	content.add_child(toggles)
	_reduced_shake = CheckButton.new()
	_reduced_shake.text = "REDUCED CAMERA SHAKE"
	_reduced_shake.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reduced_shake.toggled.connect(_on_reduced_shake_toggled)
	toggles.add_child(_reduced_shake)
	_debug_stats = CheckButton.new()
	_debug_stats.text = "DEBUG STATS"
	_debug_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_stats.toggled.connect(_on_debug_toggled)
	toggles.add_child(_debug_stats)

	var prompt_row := HBoxContainer.new()
	prompt_row.add_theme_constant_override("separation", 14)
	content.add_child(prompt_row)
	var prompt_title := Label.new()
	prompt_title.text = "PROMPT STYLE"
	prompt_title.theme_type_variation = &"EyebrowLabel"
	prompt_title.custom_minimum_size.x = 180.0
	prompt_row.add_child(prompt_title)
	_prompt_mode = OptionButton.new()
	_prompt_mode.add_item("AUTO-DETECT", 0)
	_prompt_mode.add_item("KEYBOARD", 1)
	_prompt_mode.add_item("CONTROLLER", 2)
	_prompt_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prompt_mode.item_selected.connect(_on_prompt_mode_selected)
	prompt_row.add_child(_prompt_mode)

	var reset_button := Button.new()
	reset_button.text = "RESET SETTINGS TO DEFAULTS"
	reset_button.theme_type_variation = &"DangerButton"
	reset_button.pressed.connect(_on_reset_pressed)
	content.add_child(reset_button)

	_footer_label = Label.new()
	_footer_label.theme_type_variation = &"EyebrowLabel"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_footer_label)
	set_input_device(false)

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.25
	_save_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_save_timer.timeout.connect(_flush_save)
	add_child(_save_timer)


func _add_slider_setting(
	parent: VBoxContainer,
	title_text: String,
	description: String,
	key: StringName,
	minimum: float,
	maximum: float,
	step: float
) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassPanel"
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.custom_minimum_size.x = 310.0
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"EyebrowLabel"
	copy.add_child(title)
	var detail := Label.new()
	detail.text = description
	detail.theme_type_variation = &"MutedLabel"
	copy.add_child(detail)
	var slider := HSlider.new()
	slider.theme_type_variation = &"SettingSlider"
	slider.custom_minimum_size = Vector2(220, 38)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.theme_type_variation = &"GoldLabel"
	value_label.custom_minimum_size.x = 76.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(_on_slider_changed.bind(key, value_label))
	slider.drag_ended.connect(_on_slider_drag_ended.bind(key))
	_sliders[key] = slider
	_value_labels[key] = value_label


func _load_settings() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null:
		return
	_loading = true
	for key: StringName in _sliders:
		var slider := _sliders[key] as HSlider
		var value := float(save_manager.call("get_setting", key, slider.value))
		slider.set_value_no_signal(value)
		_update_value_label(key, value, _value_labels[key] as Label)
	_reduced_shake.set_pressed_no_signal(bool(save_manager.call("get_setting", &"reduced_camera_shake", false)))
	_debug_stats.set_pressed_no_signal(bool(save_manager.call("get_setting", &"show_debug_stats", false)))
	var prompt_mode := String(save_manager.call("get_setting", &"controller_prompts", "auto"))
	_prompt_mode.select(["auto", "keyboard", "controller"].find(prompt_mode))
	_loading = false


func _on_slider_changed(value: float, key: StringName, value_label: Label) -> void:
	_update_value_label(key, value, value_label)
	if _loading:
		return
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null:
		save_manager.call("set_setting", key, value, false)
	_save_timer.start()


func _on_slider_drag_ended(_value_changed: bool, _key: StringName) -> void:
	_flush_save()


func _on_reduced_shake_toggled(value: bool) -> void:
	_set_bool(&"reduced_camera_shake", value)


func _on_debug_toggled(value: bool) -> void:
	_set_bool(&"show_debug_stats", value)


func _set_bool(key: StringName, value: bool) -> void:
	if _loading:
		return
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null:
		save_manager.call("set_setting", key, value, true)


func _on_prompt_mode_selected(index: int) -> void:
	if _loading:
		return
	var modes := ["auto", "keyboard", "controller"]
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and index >= 0 and index < modes.size():
		save_manager.call("set_setting", &"controller_prompts", modes[index], true)


func _on_reset_pressed() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null:
		save_manager.call("reset_to_defaults", true)
		_load_settings()


func _flush_save() -> void:
	if _save_timer != null:
		_save_timer.stop()
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null:
		save_manager.call("save_data")


func _update_value_label(key: StringName, value: float, label: Label) -> void:
	match key:
		&"controller_deadzone":
			label.text = "%d%%" % roundi(value * 100.0)
		&"ui_scale":
			label.text = "x%.2f" % value
		_:
			label.text = "%d%%" % roundi(value * 100.0)
