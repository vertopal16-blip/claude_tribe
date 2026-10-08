shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.52, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.30, 0.66, 0.72, 1.0);
uniform float opacity = 0.82;
uniform float wave_height = 0.05;

varying float wave;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wave = sin(world.x * 0.45 + TIME * 1.1) * 0.5 + cos(world.z * 0.38 + TIME * 0.8) * 0.5;
	VERTEX.y += wave * wave_height;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, 0.35 + wave * 0.1);
	ALBEDO = col + vec3(fresnel * 0.18);
	ALPHA = opacity;
	ROUGHNESS = 0.12;
	SPECULAR = 0.55;
}
