class_name TalkPoint
extends Interactable
## Lets the player start small talk with an NPC (currently just the manager).

@export var speaker_path: NodePath


func _ready() -> void:
	super()
	prompt_text = "Talk"


func interact(_player: Node) -> void:
	var speaker := get_node_or_null(speaker_path)
	if speaker and speaker.has_method("talk"):
		speaker.talk()
	else:
		Events.subtitle.emit(ManagerLines.TALK.pick_random(), 3.0)
