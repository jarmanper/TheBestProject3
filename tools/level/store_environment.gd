extends RefCounted
## The store's Environment (Compatibility renderer), tuned against docs/art_reference:
## near-black greenish ambient (#171B1A family) so unlit areas stay dark but readable,
## depth fog that swallows the far end of aisles, a soft glow on the fluorescent tubes,
## and filmic tonemapping that keeps the wet-floor highlights from clipping.


const FOG_END := 26.0


static func make() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.01, 0.009)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.46, 0.4)
	env.ambient_light_energy = 0.14
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# Depth fog: clear up close, fully opaque at FOG_END (the area culler stops drawing there).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.02, 0.026, 0.023)
	env.fog_light_energy = 1.0
	env.fog_density = 1.0
	env.fog_depth_begin = 3.0
	env.fog_depth_end = FOG_END
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.9
	return env
