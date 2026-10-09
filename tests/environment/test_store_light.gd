extends TestCase

var _light: StoreLight


func before_each() -> void:
	_light = StoreLight.new()
	var omni := OmniLight3D.new()
	omni.name = "Light"
	_light.add_child(omni)
	tree.root.add_child(_light)


func after_each() -> void:
	_light.free()


func test_disturbance_is_clamped_to_zero_one() -> void:
	_light.set_disturbance(5.0)
	assert_near(_light.get_disturbance(), 1.0, 0.001)
	_light.set_disturbance(-2.0)
	assert_near(_light.get_disturbance(), 0.0, 0.001)


func test_disturbance_decays_to_zero_within_half_a_second() -> void:
	_light.set_disturbance(1.0)
	_light._process(0.5)
	assert_near(_light.get_disturbance(), 0.0, 0.001)


func test_disturbance_decays_proportionally() -> void:
	_light.set_disturbance(1.0)
	_light._process(0.25)
	assert_near(_light.get_disturbance(), 0.5, 0.01)


func test_disturbance_does_not_refresh_itself() -> void:
	_light.set_disturbance(1.0)
	_light._process(0.1)
	_light._process(0.1)
	_light._process(0.1)
	_light._process(0.1)
	_light._process(0.1)
	assert_near(_light.get_disturbance(), 0.0, 0.01)
