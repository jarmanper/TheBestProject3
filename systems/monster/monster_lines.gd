class_name MonsterLines
extends RefCounted
## What the mimic says on the walkie while wearing a coworker's voice.
## Lures ask the player to come somewhere far away; the radio plays them with
## the subtly wrong `walkie_voice_mimic` variant.

const LURES := [
	"Hey, it's {name} — can you help me in {zone}?",
	"It's {name}. Can you come to {zone}? I need a hand with something.",
	"{name} here... could you come to {zone} for a sec? Just you.",
	"Hey, it's {name}. I found something in {zone}. You should come see.",
	"It's {name}. I'm stuck in {zone}. Please hurry.",
]


static func lure_line(speaker: String, zone_id: StringName, rng: RandomNumberGenerator) -> String:
	var template: String = LURES[rng.randi() % LURES.size()]
	return template.format({"name": speaker, "zone": CoworkerLines.zone_phrase(zone_id)})
