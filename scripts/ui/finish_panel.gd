extends Control

signal restart_requested
signal quit_requested

var _score_label: Label
var _time_label: Label
var _best_score_label: Label
var _best_time_label: Label
var _score_badge: Label
var _time_badge: Label
var _detail_label: Label
var _restart_button: Button
var _footer_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	visible = false


func show_result(result: Dictionary, using_controller: bool = false) -> void:
	_score_label.text = _group_number(int(result.get("score", 0)))
	_time_label.text = _format_time(float(result.get("time_seconds", 0.0)))
	_best_score_label.text = "BEST  %s" % _group_number(int(result.get("best_score", 0)))
	_best_time_label.text = "BEST  %s" % _format_record_time(float(result.get("best_time_seconds", -1.0)))
	_score_badge.visible = bool(result.get("new_best_score", false))
	_time_badge.visible = bool(result.get("new_best_time", false))
	_detail_label.text = "%s CONDITIONS     %d CRASH%s" % [
		String(result.get("weather", "Clear")).to_upper(),
		int(result.get("crashes", 0)),
		"" if int(result.get("crashes", 0)) == 1 else "ES",
	]
	set_input_device(using_controller)
	visible = true
	_restart_button.grab_focus()


func hide_panel() -> void:
	visible = false


func set_input_device(using_controller: bool) -> void:
	if _footer_label != null:
		_footer_label.text = "A  SELECT" if using_controller else "ENTER  SELECT"


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.025, 0.04, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var card := PanelContainer.new()
	card.theme_type_variation = &"GlassPanel"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -390.0
	card.offset_top = -300.0
	card.offset_right = 390.0
	card.offset_bottom = 300.0
	add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 11)
	card.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "FINISH GATE CLEARED"
	eyebrow.theme_type_variation = &"EyebrowLabel"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(eyebrow)
	var title := Label.new()
	title.text = "RUN COMPLETE"
	title.theme_type_variation = &"HeroLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 16)
	content.add_child(metrics)
	var score_card := _make_result_card("FINAL SCORE")
	score_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(score_card)
	_score_label = score_card.get_node("Content/Value") as Label
	_best_score_label = score_card.get_node("Content/Best") as Label
	_score_badge = score_card.get_node("Content/Badge") as Label
	var time_card := _make_result_card("FINISH TIME")
	time_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(time_card)
	_time_label = time_card.get_node("Content/Value") as Label
	_best_time_label = time_card.get_node("Content/Best") as Label
	_time_badge = time_card.get_node("Content/Badge") as Label

	_detail_label = Label.new()
	_detail_label.theme_type_variation = &"MutedLabel"
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_detail_label)

	var note := Label.new()
	note.text = "Clean landings bank provisional tricks. Speed, weather and narrow routes raise the reward."
	note.theme_type_variation = &"MutedLabel"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)

	_restart_button = Button.new()
	_restart_button.text = "SKI AGAIN"
	_restart_button.theme_type_variation = &"PrimaryButton"
	_restart_button.custom_minimum_size.y = 52.0
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	content.add_child(_restart_button)
	var quit_button := Button.new()
	quit_button.text = "QUIT TO DESKTOP"
	quit_button.theme_type_variation = &"GhostButton"
	quit_button.custom_minimum_size.y = 48.0
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	content.add_child(quit_button)
	_footer_label = Label.new()
	_footer_label.theme_type_variation = &"EyebrowLabel"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_footer_label)
	set_input_device(false)


func _make_result_card(title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassPanel"
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 2)
	panel.add_child(content)
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"EyebrowLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var value := Label.new()
	value.name = "Value"
	value.text = "--"
	value.theme_type_variation = &"HeroLabel"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(value)
	var best := Label.new()
	best.name = "Best"
	best.theme_type_variation = &"MutedLabel"
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(best)
	var badge := Label.new()
	badge.name = "Badge"
	badge.text = "NEW PERSONAL BEST"
	badge.theme_type_variation = &"GoldLabel"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(badge)
	return panel


func _format_time(seconds: float) -> String:
	var safe := maxf(seconds, 0.0)
	return "%02d:%04.1f" % [int(safe) / 60, fmod(safe, 60.0)]


func _format_record_time(seconds: float) -> String:
	return "--:--.-" if seconds < 0.0 else _format_time(seconds)


func _group_number(value: int) -> String:
	var source := str(maxi(value, 0))
	var grouped := ""
	for index: int in range(source.length()):
		if index > 0 and (source.length() - index) % 3 == 0:
			grouped += ","
		grouped += source[index]
	return grouped
