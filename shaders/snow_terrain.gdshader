shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 powder_color : source_color = vec3(0.91, 0.96, 1.0);
uniform vec3 packed_color : source_color = vec3(0.73, 0.86, 0.95);
uniform vec3 ice_color : source_color = vec3(0.27, 0.65, 0.82);
uniform vec3 exposed_rock_color : source_color = vec3(0.31, 0.36, 0.39);
uniform float snow_roughness : hint_range(0.0, 1.0) = 0.78;
uniform float ice_roughness : hint_range(0.0, 1.0) = 0.16;

varying vec3 local_position;
varying vec3 local_normal;
varying vec4 surface_weights;

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
	surface_weights = COLOR;
}

void fragment() {
	vec3 weights = max(surface_weights.rgb, vec3(0.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	float fine_noise = hash21(floor(local_position.xz * 1.7)) * 0.035;
	vec3 snow_color = powder_color * weights.r + packed_color * weights.g + ice_color * weights.b;
	float steepness = smoothstep(0.42, 0.72, 1.0 - local_normal.y);
	ALBEDO = mix(snow_color + fine_noise, exposed_rock_color, steepness * 0.76);
	ROUGHNESS = mix(snow_roughness, ice_roughness, weights.b);
	SPECULAR = mix(0.28, 0.72, weights.b);
	METALLIC = 0.0;
}
