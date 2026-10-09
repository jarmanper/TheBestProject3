class_name ManagerLines
extends RefCounted
## All of the store manager's flavour text in one place, so lines can be
## tuned without touching StoreManager's logic.

const WELCOME := [
	"Attention staff: the overnight shift has begun. Let's get those tasks done before sunrise.",
	"Good evening. Night crew, check the task board and get started.",
]

const HOURLY := [
	"It's %s. Keep an eye on the clock, folks.",
	"%s, and the store's still standing. Keep moving.",
	"Mark it down, it's %s.",
]

## Mundane-on-the-surface PA filler, said occasionally with no task attached.
const PA_FLAVOUR := [
	"Cleanup on aisle... actually, never mind. It's handled.",
	"If anyone's in the storage room, the door locks itself. Just so you know.",
	"Reminder: the back exit alarm has been disabled for inventory. Don't worry about it.",
	"The temperature in the freezer keeps resetting itself. Odd.",
	"Please remember to clock out before you leave. Or clock in. Whichever you're doing.",
	"We appreciate your continued effort tonight.",
]

const TASK_COMPLETED := [
	"Nice work, that's one off the list.",
	"Appreciate it. One less thing to worry about.",
	"Good, keep that pace up.",
]

const TASK_FAILED := [
	"Well, that didn't get done in time. I'll make a note of it.",
	"Someone's getting a write-up for that one.",
	"That was supposed to be handled already.",
]

const COWORKER_MISSING := [
	"Has anyone seen %s? They're not answering the radio.",
	"If %s is listening, please check in. Now, please.",
	"I'm getting worried about %s. Someone go find them.",
]

const TALK := [
	"Just get your tasks done and you can clock out at six.",
	"Don't mind the noises, this building settles.",
	"If you see something strange, radio it in. Don't investigate alone.",
	"I'll be here in the office if you need anything.",
]


static func random_hourly(clock_text: String) -> String:
	return (HOURLY.pick_random() as String) % clock_text


static func random_missing(coworker_name: String) -> String:
	return (COWORKER_MISSING.pick_random() as String) % coworker_name
