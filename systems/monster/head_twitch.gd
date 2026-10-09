class_name HeadTwitch
extends SkeletonModifier3D
## Disguise tell: snaps the `head` bone to an odd angle for a moment, on top of
## whatever animation is playing. Add as a child of the model's Skeleton3D.

const BONE_NAME := &"head"
const RETURN_SPEED := 9.0   ## how fast the head eases back (per second)

var _offset := Quaternion.IDENTITY
var _hold_left := 0.0


## Snap the head by `degrees` (random axis mix) and hold for `hold` seconds.
func twitch(degrees: float, hold: float, rng: RandomNumberGenerator) -> void:
	var axis := Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-1.0, 1.0)).normalized()
	_offset = Quaternion(axis, deg_to_rad(degrees) * (1.0 if rng.randf() < 0.5 else -1.0))
	_hold_left = hold


func has_head_bone() -> bool:
	var skeleton := get_skeleton()
	return skeleton != null and skeleton.find_bone(BONE_NAME) >= 0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var bone := skeleton.find_bone(BONE_NAME)
	if bone < 0:
		return
	if _hold_left > 0.0:
		_hold_left -= delta
	else:
		_offset = _offset.slerp(Quaternion.IDENTITY, clampf(RETURN_SPEED * delta, 0.0, 1.0))
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * _offset)
