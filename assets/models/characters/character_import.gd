@tool
extends EditorScenePostImport
## Post-import step for the character GLBs (set as import_script/path in each .glb.import by
## art_source/blender/characters/build_characters.py). glTF has no loop flag, so every clip loops
## except the one-shot monster clips.

const ONE_SHOT: Array[StringName] = [&"attack", &"reveal"]


func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for clip in player.get_animation_list():
			var animation := player.get_animation(clip)
			animation.loop_mode = Animation.LOOP_NONE if clip in ONE_SHOT else Animation.LOOP_LINEAR
	return scene
