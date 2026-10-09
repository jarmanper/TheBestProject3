extends AudioStreamPlayer3D
## A quiet positional ambience loop (freezer hum, back-room drone) placed in the level.
## The stream comes from Sfx at runtime, so it loops (Sfx enables looping for ambience ids)
## and a missing file only warns once.

@export var sound_id: StringName = &"amb_backroom"


func _ready() -> void:
	bus = &"Ambience"
	stream = Sfx.get_stream(sound_id)
	if stream:
		play()
