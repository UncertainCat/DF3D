extends "res://tests/render_attribution_live.gd"

func run():
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/billboard_sprite.gdshader")
	var original: Shader = material.shader
	mesh.surface_set_material(0,material)
	var enabled := MeshInstance3D.new()
	enabled.mesh = mesh
	root.add_child(enabled)
	var hidden := MeshInstance3D.new()
	hidden.mesh = mesh
	var second_material := ShaderMaterial.new()
	second_material.shader = original
	hidden.material_override = second_material
	hidden.layers = 0
	root.add_child(hidden)
	var instances := MultiMeshInstance3D.new()
	instances.multimesh = MultiMesh.new()
	instances.multimesh.mesh = mesh
	instances.multimesh.instance_count = 8
	instances.multimesh.visible_instance_count = 3
	root.add_child(instances)
	categories = {"fixture":[enabled,hidden,instances]}
	var counts: Dictionary = census().fixture
	assert(counts.nodes == 3 and counts.enabled_nodes == 2)
	assert(counts.instances == 4 and counts.surfaces == 2 and counts.triangles_times_instances == 4)
	var restore := shader_variant()
	assert(restore.size() == 2) # Shared materials changed once, shaders remain shared.
	assert(material.shader == second_material.shader)
	assert(not material.shader.code.contains("ALPHA = COLOR.a;"))
	assert(material.shader.code.contains("discard"))
	for entry in restore: entry[0].shader = entry[1]
	assert(material.shader == original)
	print("RENDER_ATTRIBUTION_TEST_PASS")
	quit()
