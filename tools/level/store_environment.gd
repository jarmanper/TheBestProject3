extends RefCounted
## The store's Environment (Compatibility renderer), tuned against docs/art_reference:
## near-black greenish ambient (#171B1A family) so unlit areas stay dark but readable,
## depth fog that swallows the far end of aisles, a soft glow on the fluorescent tubes,
## and filmic tonemapping that keeps the wet-floor highlights from clipping.


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
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.03, 0.038, 0.034)
	env.fog_light_energy = 1.0
	env.fog_density = 0.035
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
