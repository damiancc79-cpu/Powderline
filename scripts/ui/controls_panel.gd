extends Control

signal back_requested

var _back_button: Button
var _keyboard_column: PanelContainer
var _controller_column: PanelContainer
var _footer_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	visible = false


func show_panel(using_controller: bool = false) -> void:
	set_input_device(using_controller)
	visible = true
	_back_button.grab_focus()


func hide_panel() -> void:
	visible = false


func set_input_device(using_controller: bool) -> void:
	if _keyboard_column == null:
		return
	_keyboard_column.modulate = Color(0.82, 0.88, 0.92, 0.88) if using_controller else Color.WHITE
	_controller_column.modulate = Color.WHITE if using_controller else Color(0.82, 0.88, 0.92, 0.88)
	_footer_label.text = "B  BACK" if using_controller else "ESC  BACK"


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.025, 0.04, 0.90)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 44)
	safe.add_theme_constant_override("margin_top", 28)
	safe.add_theme_constant_override("margin_right", 44)
	safe.add_theme_constant_override("margin_bottom", 28)
	add_child(safe)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	safe.add_child(content)

	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(titles)
	var eyebrow := Label.new()
	eyebrow.text = "FIELD GUIDE"
	eyebrow.theme_type_variation = &"EyebrowLabel"
	titles.add_child(eyebrow)
	var title := Label.new()
	title.text = "CONTROLS + TRICK PAIRS"
	title.theme_type_variation = &"HeroLabel"
	titles.add_child(title)
	_back_button = Button.new()
	_back_button.text = "BACK"
	_back_button.theme_type_variation = &"GhostButton"
	_back_button.custom_minimum_size = Vector2(126, 48)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	title_row.add_child(_back_button)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	content.add_child(columns)
	_keyboard_column = _make_control_column("KEYBOARD", [
		["W", "Tuck / accelerate"],
		["S", "Brake / snowplow"],
		["A / D", "Carve left / right"],
		["SPACE", "Pop / jump"],
		["Q / E", "Trick modifiers"],
		["SHIFT", "Strong tuck / air tweak"],
		["R", "Latest checkpoint"],
		["ESC", "Pause"],
	])
	_keyboard_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_keyboard_column)
	_controller_column = _make_control_column("CONTROLLER", [
		["LEFT STICK", "Steer + tuck / brake"],
		["SOUTH / A", "Pop / jump"],
		["WEST / X", "Trick modifier 1"],
		["NORTH / Y", "Trick modifier 2"],
		["LEFT BUMPER", "Strong tuck / air tweak"],
		["START", "Pause"],
		["UI: A / B", "Select / back"],
		["DEAD ZONE", "Adjustable in Settings"],
	])
	_controller_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_controller_column)

	var tricks := PanelContainer.new()
	tricks.theme_type_variation = &"GlassPanel"
	content.add_child(tricks)
	var trick_content := VBoxContainer.new()
	trick_content.add_theme_constant_override("separation", 6)
	tricks.add_child(trick_content)
	var trick_title := Label.new()
	trick_title.text = "TWO-BUTTON TRICKS  /  HOLD BOTH WHILE AIRBORNE"
	trick_title.theme_type_variation = &"GoldLabel"
	trick_content.add_child(trick_title)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 7)
	trick_content.add_child(grid)
	_add_trick(grid, "Q + A", "SPIN LEFT")
	_add_trick(grid, "Q + D", "SPIN RIGHT")
	_add_trick(grid, "E + W", "FRONT FLIP")
	_add_trick(grid, "E + S", "BACKFLIP")
	_add_trick(grid, "Q + E", "GRAB")
	_add_trick(grid, "SHIFT + A", "LEFT TWEAK")
	_add_trick(grid, "SHIFT + D", "RIGHT TWEAK")
	_add_trick(grid, "LAND CLEAN", "BANK POINTS")

	_footer_label = Label.new()
	_footer_label.theme_type_variation = &"EyebrowLabel"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_footer_label)
	set_input_device(false)


func _make_control_column(title_text: String, rows: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassPanel"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	panel.add_child(content)
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"AccentLabel"
	content.add_child(title)
	for row_data: Array in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		content.add_child(row)
		var key := Label.new()
		key.text = String(row_data[0])
		key.theme_type_variation = &"GoldLabel"
		key.custom_minimum_size.x = 146.0
		row.add_child(key)
		var action := Label.new()
		action.text = String(row_data[1])
		action.theme_type_variation = &"MutedLabel"
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(action)
	return panel


func _add_trick(grid: GridContainer, input_text: String, trick_name: String) -> void:
	var input_label := Label.new()
	input_label.text = input_text
	input_label.theme_type_variation = &"GoldLabel"
	grid.add_child(input_label)
	var trick_label := Label.new()
	trick_label.text = trick_name
	trick_label.theme_type_variation = &"MutedLabel"
	trick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(trick_label)
