extends RefCounted

## Runtime theme keeps the UI self-contained and lets accessibility scale take
## effect immediately without depending on an external font or theme resource.

const INK := Color("eaf7ff")
const MUTED := Color("9bb5c7")
const NIGHT := Color("07141f")
const PANEL := Color(0.035, 0.105, 0.16, 0.94)
const PANEL_SOFT := Color(0.04, 0.13, 0.19, 0.82)
const CYAN := Color("69e5ff")
const BLUE := Color("148bb8")
const GOLD := Color("ffd166")
const RED := Color("ff6b73")
const GREEN := Color("7df0b2")


static func create(ui_scale: float = 1.0) -> Theme:
	var scale := clampf(ui_scale, 0.80, 1.35)
	var theme := Theme.new()
	theme.default_font_size = roundi(17.0 * scale)

	theme.set_color(&"font_color", &"Label", INK)
	theme.set_color(&"font_shadow_color", &"Label", Color(0.0, 0.0, 0.0, 0.7))
	theme.set_constant(&"shadow_offset_x", &"Label", roundi(1.0 * scale))
	theme.set_constant(&"shadow_offset_y", &"Label", roundi(2.0 * scale))
	theme.set_font_size(&"font_size", &"Label", roundi(17.0 * scale))

	theme.set_color(&"font_color", &"Button", INK)
	theme.set_color(&"font_hover_color", &"Button", Color.WHITE)
	theme.set_color(&"font_pressed_color", &"Button", Color.WHITE)
	theme.set_color(&"font_focus_color", &"Button", Color.WHITE)
	theme.set_color(&"font_disabled_color", &"Button", Color(0.55, 0.65, 0.70, 0.6))
	theme.set_font_size(&"font_size", &"Button", roundi(17.0 * scale))
	theme.set_stylebox(&"normal", &"Button", _box(Color(0.06, 0.18, 0.25, 0.96), Color(0.18, 0.39, 0.49, 0.9), 1, 10, 16, 10, scale))
	theme.set_stylebox(&"hover", &"Button", _box(Color(0.07, 0.28, 0.38, 0.98), CYAN, 1, 10, 16, 10, scale))
	theme.set_stylebox(&"pressed", &"Button", _box(Color(0.04, 0.40, 0.52, 1.0), Color.WHITE, 1, 10, 16, 10, scale))
	theme.set_stylebox(&"focus", &"Button", _box(Color(0, 0, 0, 0), GOLD, 3, 12, 15, 9, scale))
	theme.set_stylebox(&"disabled", &"Button", _box(Color(0.04, 0.10, 0.13, 0.8), Color(0.18, 0.28, 0.32, 0.7), 1, 10, 16, 10, scale))

	theme.set_stylebox(&"panel", &"PanelContainer", _box(PANEL, Color(0.25, 0.58, 0.70, 0.45), 1, 18, 22, 18, scale, 12))
	theme.set_stylebox(&"panel", &"Panel", _box(PANEL, Color(0.25, 0.58, 0.70, 0.45), 1, 18, 18, 14, scale, 12))

	theme.set_color(&"font_color", &"CheckButton", INK)
	theme.set_color(&"font_hover_color", &"CheckButton", Color.WHITE)
	theme.set_font_size(&"font_size", &"CheckButton", roundi(16.0 * scale))
	theme.set_color(&"font_color", &"HSlider", INK)
	theme.set_stylebox(&"slider", &"HSlider", _line_box(Color(0.12, 0.30, 0.38, 1.0), 6, scale))
	theme.set_stylebox(&"grabber_area", &"HSlider", _line_box(CYAN, 6, scale))
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", _line_box(Color.WHITE, 7, scale))

	_add_variations(theme, scale)
	return theme


static func _add_variations(theme: Theme, scale: float) -> void:
	theme.set_type_variation(&"GlassPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"GlassPanel", _box(PANEL_SOFT, Color(0.35, 0.75, 0.86, 0.34), 1, 14, 18, 13, scale, 8))

	theme.set_type_variation(&"Chip", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Chip", _box(Color(0.03, 0.13, 0.18, 0.90), Color(0.38, 0.77, 0.86, 0.48), 1, 999, 13, 7, scale))

	theme.set_type_variation(&"ToastPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"ToastPanel", _box(Color(0.02, 0.10, 0.14, 0.96), CYAN, 2, 12, 18, 11, scale, 8))

	theme.set_type_variation(&"HeroLabel", &"Label")
	theme.set_font_size(&"font_size", &"HeroLabel", roundi(36.0 * scale))
	theme.set_color(&"font_color", &"HeroLabel", Color.WHITE)

	theme.set_type_variation(&"MetricLabel", &"Label")
	theme.set_font_size(&"font_size", &"MetricLabel", roundi(27.0 * scale))
	theme.set_color(&"font_color", &"MetricLabel", Color.WHITE)

	theme.set_type_variation(&"EyebrowLabel", &"Label")
	theme.set_font_size(&"font_size", &"EyebrowLabel", roundi(12.0 * scale))
	theme.set_color(&"font_color", &"EyebrowLabel", MUTED)
	theme.set_constant(&"outline_size", &"EyebrowLabel", 1)

	theme.set_type_variation(&"MutedLabel", &"Label")
	theme.set_font_size(&"font_size", &"MutedLabel", roundi(14.0 * scale))
	theme.set_color(&"font_color", &"MutedLabel", MUTED)

	theme.set_type_variation(&"AccentLabel", &"Label")
	theme.set_color(&"font_color", &"AccentLabel", CYAN)
	theme.set_font_size(&"font_size", &"AccentLabel", roundi(18.0 * scale))

	theme.set_type_variation(&"GoldLabel", &"Label")
	theme.set_color(&"font_color", &"GoldLabel", GOLD)
	theme.set_font_size(&"font_size", &"GoldLabel", roundi(18.0 * scale))

	theme.set_type_variation(&"DangerLabel", &"Label")
	theme.set_color(&"font_color", &"DangerLabel", RED)

	theme.set_type_variation(&"DebugLabel", &"Label")
	theme.set_font_size(&"font_size", &"DebugLabel", roundi(12.0 * scale))
	theme.set_color(&"font_color", &"DebugLabel", Color("c0f4ff"))

	theme.set_type_variation(&"PrimaryButton", &"Button")
	theme.set_stylebox(&"normal", &"PrimaryButton", _box(Color(0.04, 0.46, 0.61, 0.98), CYAN, 1, 10, 16, 10, scale))
	theme.set_stylebox(&"hover", &"PrimaryButton", _box(Color(0.05, 0.58, 0.72, 1.0), Color.WHITE, 2, 10, 16, 10, scale))
	theme.set_stylebox(&"pressed", &"PrimaryButton", _box(Color(0.03, 0.34, 0.46, 1.0), Color.WHITE, 1, 10, 16, 10, scale))

	theme.set_type_variation(&"DangerButton", &"Button")
	theme.set_stylebox(&"normal", &"DangerButton", _box(Color(0.34, 0.08, 0.12, 0.95), Color(0.78, 0.23, 0.29, 0.8), 1, 10, 16, 10, scale))
	theme.set_stylebox(&"hover", &"DangerButton", _box(Color(0.48, 0.10, 0.15, 1.0), RED, 2, 10, 16, 10, scale))

	theme.set_type_variation(&"GhostButton", &"Button")
	theme.set_stylebox(&"normal", &"GhostButton", _box(Color(0.02, 0.08, 0.11, 0.35), Color(0.35, 0.55, 0.63, 0.35), 1, 10, 16, 10, scale))

	theme.set_type_variation(&"SettingSlider", &"HSlider")
	theme.set_icon(&"grabber", &"SettingSlider", _circle_texture(8, CYAN))
	theme.set_icon(&"grabber_highlight", &"SettingSlider", _circle_texture(9, Color.WHITE))


static func _box(
	fill: Color,
	border: Color,
	border_width: int,
	radius: int,
	horizontal_padding: int,
	vertical_padding: int,
	scale: float,
	shadow_size: int = 0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	var width := maxi(roundi(float(border_width) * scale), border_width)
	box.border_width_left = width
	box.border_width_top = width
	box.border_width_right = width
	box.border_width_bottom = width
	box.border_color = border
	var scaled_radius := roundi(float(radius) * scale)
	box.corner_radius_top_left = scaled_radius
	box.corner_radius_top_right = scaled_radius
	box.corner_radius_bottom_left = scaled_radius
	box.corner_radius_bottom_right = scaled_radius
	box.content_margin_left = float(horizontal_padding) * scale
	box.content_margin_right = float(horizontal_padding) * scale
	box.content_margin_top = float(vertical_padding) * scale
	box.content_margin_bottom = float(vertical_padding) * scale
	if shadow_size > 0:
		box.shadow_color = Color(0.0, 0.02, 0.04, 0.5)
		box.shadow_size = roundi(float(shadow_size) * scale)
		box.shadow_offset = Vector2(0.0, 4.0 * scale)
	return box


static func _line_box(fill: Color, height: int, scale: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.corner_radius_top_left = roundi(4.0 * scale)
	box.corner_radius_top_right = roundi(4.0 * scale)
	box.corner_radius_bottom_left = roundi(4.0 * scale)
	box.corner_radius_bottom_right = roundi(4.0 * scale)
	box.content_margin_top = float(height) * 0.5 * scale
	box.content_margin_bottom = float(height) * 0.5 * scale
	return box


static func _circle_texture(radius: int, color: Color) -> ImageTexture:
	var diameter := radius * 2 + 2
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := Vector2(radius + 1, radius + 1)
	for y: int in range(diameter):
		for x: int in range(diameter):
			var distance := Vector2(x, y).distance_to(center)
			if distance <= float(radius):
				var alpha := clampf(float(radius) + 0.5 - distance, 0.0, 1.0)
				image.set_pixel(x, y, Color(color, color.a * alpha))
	return ImageTexture.create_from_image(image)
