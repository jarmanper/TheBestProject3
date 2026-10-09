class_name CrtPostFx
extends CanvasLayer
## Full-screen screen-colour pass (crt.gdshader) over everything on lower canvas layers.
## Brightness (GameState.brightness) always multiplies the final colour -- the pass itself is
## never hidden. The CRT look (GameState.crt_enabled) is toggled by zeroing its strength
## uniforms instead of hiding the layer, so brightness keeps applying with CRT off.
## Keeps animating while the game is paused.

const CRT_STRENGTH_DEFAULTS := {
	&"curvature": 0.07,
	&"vignette_strength": 0.6,
	&"scanline_strength": 0.11,
	&"grain_strength": 0.045,
	&"chroma_pixels": 1.25,
	&"desaturation": 0.2,
	&"shadow_lift": 0.65,
	&"flicker_strength": 0.012,
}

@onready var _screen: ColorRect = $Screen
var _material: ShaderMaterial
var _crt_on: bool


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	# Duplicate: the ShaderMaterial sub-resource in postfx.tscn is shared across every
	# instance of this scene, so without this, two live PostFX nodes (e.g. one left over
	# from a previous test) would stomp on each other's uniforms.
	_material = (_screen.material as ShaderMaterial).duplicate()
	_screen.material = _material
	_crt_on = not GameState.crt_enabled   # force the first _process to apply it
	_apply()


func _process(_delta: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"brightness", GameState.brightness)
	if _crt_on != GameState.crt_enabled:
		_apply()


func _apply() -> void:
	_crt_on = GameState.crt_enabled
	for key in CRT_STRENGTH_DEFAULTS:
		_material.set_shader_parameter(key, CRT_STRENGTH_DEFAULTS[key] if _crt_on else 0.0)
	_material.set_shader_parameter(&"brightness", GameState.brightness)
