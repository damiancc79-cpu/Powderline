extends Control

signal resume_requested
signal restart_requested
signal controls_requested
signal settings_requested
signal quit_requested

var _resume_button: Button
var _run_detail_label: Label
var _footer_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	visible = false


func show_menu() -> void:
	_refresh_run_details()
	visible = true
	_resume_button.grab_focus()


func hide_menu() -> void:
	visible = false


func set_input_device(using_controller: bool) -> void:
	if _footer_label == null:
		return
	_footer_label.text = "B  BACK     A  SELECT" if using_controller else "ESC  BACK     ENTER  SELECT"


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.025, 0.04, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var card := PanelContainer.new()
	card.theme_type_variation = &"GlassPanel"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -248.0
	card.offset_top = -282.0
	card.offset_right = 248.0
	card.offset_bottom = 282.0
	add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)

	var eyebrow := Label.new()
	eyebrow.text = "POWDERLINE  /  RUN ON HOLD"
	eyebrow.theme_type_variation = &"EyebrowLabel"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(eyebrow)

	var title := Label.new()
	title.text = "PAUSED"
	title.theme_type_variation = &"HeroLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	_run_detail_label = Label.new()
	_run_detail_label.theme_type_variation = &"MutedLabel"
	_run_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_run_detail_label)

	var separator := HSeparator.new()
	content.add_child(separator)

	_resume_button = _make_button("RESUME RUN", &"PrimaryButton")
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	content.add_child(_resume_button)

	var restart_button := _make_button("RESTART RUN", &"DangerButton")
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	content.add_child(restart_button)

	var controls_button := _make_button("CONTROLS + TRICKS")
	controls_button.pressed.connect(func() -> void: controls_requested.emit())
	content.add_child(controls_button)

	var settings_button := _make_button("SETTINGS")
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	content.add_child(settings_button)

	var quit_button := _make_button("QUIT TO DESKTOP", &"GhostButton")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	content.add_child(quit_button)

	_footer_label = Label.new()
	_footer_label.theme_type_variation = &"EyebrowLabel"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_footer_label)
	set_input_device(false)


func _make_button(label_text: String, variation: StringName = &"") -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 48.0
	button.focus_mode = Control.FOCUS_ALL
	if not variation.is_empty():
		button.theme_type_variation = variation
	return button


func _refresh_run_details() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		_run_detail_label.text = ""
		return
	var score := int(state.get("banked_score"))
	var seconds := float(state.get("elapsed_seconds"))
	_run_detail_label.text = "SCORE  %s     TIME  %s" % [_group_number(score), _format_time(seconds)]


func _format_time(seconds: float) -> String:
	var safe := maxf(seconds, 0.0)
	return "%02d:%04.1f" % [int(safe) / 60, fmod(safe, 60.0)]


func _group_number(value: int) -> String:
	var source := str(maxi(value, 0))
	var grouped := ""
	for index: int in range(source.length()):
		if index > 0 and (source.length() - index) % 3 == 0:
			grouped += ","
		grouped += source[index]
	return grouped
