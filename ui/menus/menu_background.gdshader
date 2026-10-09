shader_type canvas_item;
// Dark flickering CRT background for the title screen: charcoal glass with a faint
// fluorescent glow, a slow rolling interference band, noise and an occasional flicker.

uniform vec4 base_color : source_color = vec4(0.055, 0.065, 0.062, 1.0);
uniform vec4 glow_color : source_color = vec4(0.847, 0.827, 0.659, 1.0);
uniform vec4 red_color : source_color = vec4(0.725, 0.231, 0.196, 1.0);
uniform float glow_strength = 0.06;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// A cold fluorescent glow from above, like a single tube in a dark aisle.
	float glow = exp(-pow((uv.x - 0.5) * 2.2, 2.0) - uv.y * 2.6);
	// Faint shelf silhouettes: vertical bands on both sides.
	float shelves = step(0.5, fract(uv.y * 9.0)) * (smoothstep(0.32, 0.12, uv.x) + smoothstep(0.68, 0.88, uv.x)) * 0.012;
	vec3 col = base_color.rgb + glow_color.rgb * glow * glow_strength + vec3(shelves);
	// Rolling interference band.
	float band = smoothstep(0.08, 0.0, abs(fract(uv.y - t * 0.045) - 0.5));
	col += glow_color.rgb * band * 0.025;
	// Emergency-red tint creeping in from the bottom.
	col = mix(col, red_color.rgb * 0.25, smoothstep(0.75, 1.0, uv.y) * 0.25);
	// Grain and flicker.
	col += (hash(floor(FRAGCOORD.xy * 0.5) + floor(t * 20.0)) - 0.5) * 0.035;
	float flicker = 1.0 - 0.35 * step(0.965, hash(vec2(floor(t * 12.0), 5.1)));
	COLOR = vec4(col * flicker, 1.0);
}
