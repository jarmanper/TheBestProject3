class_name CoworkerLines
extends RefCounted
## What the AI coworkers say on the walkie. Chatter always tells the truth about
## where they are, which is how a careful player catches the mimic lying.

## How people say each zone over the radio ("in the storage room", "in Aisle 3").
const ZONE_PHRASES := {
	&"aisle_1": "Aisle 1",
	&"aisle_2": "Aisle 2",
	&"aisle_3": "Aisle 3",
	&"aisle_4": "Aisle 4",
	&"dairy": "dairy",
	&"frozen": "frozen foods",
	&"produce": "produce",
	&"checkout": "the checkouts",
	&"service_desk": "customer service",
	&"hallway": "the back hallway",
	&"storage": "the storage room",
	&"break_room": "the break room",
	&"office": "the manager's office",
	&"janitor": "the janitor closet",
}

## Task titles are imperative ("Mop the spill in Aisle 3"), hence "gotta {task}".
const WORKING := [
	"It's {name}. I'm in {zone}. Gotta {task}.",
	"{name} here. Still in {zone}, trying to {task}.",
	"Hey, {name} here — over in {zone}. About to {task}.",
]
const HEADING := [
	"{name} here. Walking through {zone}, got a job to do.",
	"It's {name}. In {zone}, on my way to a job.",
]
const RESTING := [
	"It's {name}. Taking five in {zone}.",
	"{name} here. I'm in {zone}. Quiet night... too quiet.",
	"Anyone else hear that? It's {name}, I'm in {zone}.",
	"{name} checking in from {zone}.",
]
const PANIC := [
	"It's {name} — that's NOT one of us! RUN!",
	"{name} here — something's in {zone}! It's not a person!",
	"Oh God — it's {name} — it's in {zone}, get out of there!",
]


static func zone_phrase(zone_id: StringName) -> String:
	if ZONE_PHRASES.has(zone_id):
		return ZONE_PHRASES[zone_id]
	if zone_id == &"":
		return "the store"
	return "the " + Catalog.zone_name(zone_id).to_lower()


## Truthful check-in. `activity` is &"working", &"heading" or &"resting".
static func chatter_line(speaker: String, zone_id: StringName, activity: StringName, task_title: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = RESTING
	if activity == &"working" and not task_title.is_empty():
		pool = WORKING
	elif activity == &"heading":
		pool = HEADING
	return _fill(_pick(pool, rng), speaker, zone_id, task_title)


static func panic_line(speaker: String, zone_id: StringName, rng: RandomNumberGenerator) -> String:
	return _fill(_pick(PANIC, rng), speaker, zone_id, "")


static func _fill(template: String, speaker: String, zone_id: StringName, task_title: String) -> String:
	return template.format({
		"name": speaker,
		"zone": zone_phrase(zone_id),
		"task": task_title.to_lower() if not task_title.is_empty() else "finish a job",
	})


static func _pick(pool: Array, rng: RandomNumberGenerator) -> String:
	return pool[rng.randi() % pool.size()]
