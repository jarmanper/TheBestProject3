shader_type canvas_item;
render_mode unshaded;
// CRT screen like reference image 1: slight barrel distortion, dark rounded bezel, vignette,
// faint scanlines, animated grain, slight chromatic offset, shadows lifted toward Midnight
// Charcoal (#171B1A) and mild desaturation. Applied to the whole screen behind the HUD.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform float curvature : hint_range(0.0, 0.3) = 0.07;
uniform float zoom : hint_range(0.8, 1.2) = 1.015;
uniform float corner_radius : hint_range(0.0, 0.4) = 0.12;
uniform float edge_softness : hint_range(0.0, 0.05) = 0.012;
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.6;
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.11;
uniform float scanline_period = 3.0;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.045;
uniform float chroma_pixels = 1.25;
uniform vec4 shadow_color : source_color = vec4(0.090, 0.106, 0.102, 1.0);
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.65;
uniform float desaturation : hint_range(0.0, 1.0) = 0.2;
uniform vec4 bezel_color : source_color = vec4(0.028, 0.032, 0.03, 1.0);
uniform float flicker_strength : hint_range(0.0, 0.1) = 0.012;
// Horror brightness setting (GameState.brightness): 0.4..1.0, applied to the 3D view
// regardless of the CRT toggle above.
uniform float brightness : hint_range(0.4, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;   // width / height
	vec2 c = SCREEN_UV * 2.0 - 1.0;
	// Barrel distortion, stronger along the long axis like a 4:3 tube stretched wide.
	vec2 d = c * (1.0 + curvature * vec2(c.y * c.y, c.x * c.x * 1.4)) / zoom;
	vec2 uv = d * 0.5 + 0.5;

	// Rounded screen edge in an aspect-correct space.
	vec2 p = abs(d) * vec2(aspect, 1.0);
	vec2 b = vec2(aspect, 1.0) - corner_radius;
	float dist = length(max(p - b, 0.0)) - corner_radius;
	float inside = 1.0 - smoothstep(-edge_softness, 0.0, dist);

	vec2 radial = normalize(c + 1e-5) * chroma_pixels * SCREEN_PIXEL_SIZE * dot(c, c);
	vec3 col;
	col.r = texture(screen_texture, uv + radial).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - radial).b;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), desaturation);
	col = mix(col, mix(shadow_color.rgb, vec3(1.0), col), shadow_lift);

	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 6.2831853 / scanline_period);
	col *= 1.0 - scanline_strength * scan;
	col += (hash(FRAGCOORD.xy + fract(TIME * 7.13) * 917.0) - 0.5) * grain_strength;

	float vignette = 1.0 - vignette_strength * pow(clamp(length(c * vec2(0.82, 1.0)) / 1.3, 0.0, 1.0), 2.4);
	float flicker = 1.0 + flicker_strength * (hash(vec2(floor(TIME * 24.0), 3.7)) - 0.5);
	col *= vignette * flicker * brightness;

	// Bezel: dark plastic with a faint inner glow near the glass edge.
	vec3 bezel = bezel_color.rgb + vec3(0.02) * smoothstep(0.06, 0.0, dist);
	COLOR = vec4(mix(bezel, col, inside), 1.0);
}
