shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform float opacity : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	float groove = 0.72 + abs(UV.x - 0.5) * 0.28;
	ALBEDO = COLOR.rgb * groove;
	ALPHA = COLOR.a * opacity;
	ROUGHNESS = 0.92;
}
