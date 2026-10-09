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


func test_a_dark_light_is_hidden_so_it_does_not_use_up_the_renderer_light_limit() -> void:
	var dark := StoreLight.new()
	dark.starts_off = true
	var omni := OmniLight3D.new()
	omni.name = "Light"
	dark.add_child(omni)
	tree.root.add_child(dark)
	assert_false(omni.visible, "a starts_off light is hidden")
	assert_true(_light.get_node("Light").visible, "a lit light is visible")
	dark.free()


func test_keeps_the_scene_range_and_colour() -> void:
	var light := StoreLight.new()
	var omni := OmniLight3D.new()
	omni.name = "Light"
	omni.omni_range = 5.5
	omni.light_color = Color.RED
	light.add_child(omni)
	tree.root.add_child(light)
	assert_near(omni.omni_range, 5.5, 0.001, "range from the level")
	assert_eq(omni.light_color, Color.RED, "colour from the level")
	assert_false(omni.shadow_enabled, "never casts shadows")
	light.free()


func test_drives_only_the_emissive_tube_surface_of_a_two_surface_fixture() -> void:
	var fixture := MeshInstance3D.new()
	fixture.name = "Fixture"
	var mesh := ArrayMesh.new()
	var housing := StandardMaterial3D.new()
	var tube := StandardMaterial3D.new()
	tube.emission_enabled = true
	tube.emission_energy_multiplier = 3.0
	for material in [housing, tube]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	fixture.mesh = mesh
	var light := StoreLight.new()
	light.fixture_path = ^"Fixture"
	var omni := OmniLight3D.new()
	omni.name = "Light"
	light.add_child(omni)
	light.add_child(fixture)
	tree.root.add_child(light)
	assert_true(fixture.material_override == null, "no override over the whole fixture")
	assert_true(fixture.get_surface_override_material(0) == null, "housing keeps its material")
	var own := fixture.get_surface_override_material(1) as StandardMaterial3D
	assert_true(own != null and own != tube, "the tube gets its own copy")
	if own:
		assert_near(own.emission_energy_multiplier, 3.0, 0.001, "full brightness keeps the tube's own emission")
		light._set_energy_fraction(0.5)
		assert_near(own.emission_energy_multiplier, 1.5, 0.001, "dimming scales the tube's emission")
	assert_near(tube.emission_energy_multiplier, 3.0, 0.001, "the shared material is untouched")
	light.free()
