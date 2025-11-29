extends MeshInstance3D

const SHADER_PATH = "res://compute_version/marching_cubes.glsl"

# Configuration
var chunk_coord: Vector3i
var grid_size: int = 32
var scale_factor: float = 1.0
var terrain_height: float = 32.0
var iso_level: float = 0.0

signal generation_complete(coord)

func start_generation(p_coord, p_grid, p_iso, p_scale, p_height, p_rd, p_shader):
	chunk_coord = p_coord
	grid_size = p_grid
	iso_level = p_iso
	scale_factor = p_scale
	terrain_height = p_height
	
	_run_compute(p_rd, p_shader)

func _run_compute(rd: RenderingDevice, shader_rid: RID):
	# 1. Setup Buffers using the shared RenderingDevice
	
	# Output Buffer (Vertices)
	# Max vertices: Grid^3 * 5 triangles * 3 verts * 3 floats * 4 bytes
	var max_elements = (grid_size * grid_size * grid_size) * 15 * 3
	var output_bytes = max_elements * 4 
	var output_buffer = rd.storage_buffer_create(output_bytes)
	
	# Counter Buffer (Atomic Counter)
	# 1 uint (4 bytes), initialized to 0
	var counter_bytes = PackedByteArray([0, 0, 0, 0])
	var counter_buffer = rd.storage_buffer_create(4, counter_bytes)
	
	# Config Uniform Buffer
	# Layout:
	# 0-11: vec3 chunk_offset (3 floats)
	# 12-15: padding (float)
	# 16-19: int grid_size
	# 20-23: float iso_level
	# 24-27: float terrain_height
	# 28-31: float scale_factor
	
	var config_bytes = PackedByteArray()
	config_bytes.resize(32)
	
	config_bytes.encode_float(0, float(chunk_coord.x))
	config_bytes.encode_float(4, float(chunk_coord.y))
	config_bytes.encode_float(8, float(chunk_coord.z))
	config_bytes.encode_float(12, 0.0) # Padding
	
	config_bytes.encode_s32(16, int(grid_size))
	config_bytes.encode_float(20, iso_level)
	config_bytes.encode_float(24, terrain_height)
	config_bytes.encode_float(28, scale_factor)
	
	var uniform_buffer = rd.uniform_buffer_create(config_bytes.size(), config_bytes)
	
	# 2. Create Uniform Sets
	var uniform_output = RDUniform.new()
	uniform_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_output.binding = 0
	uniform_output.add_id(output_buffer)
	
	var uniform_counter = RDUniform.new()
	uniform_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_counter.binding = 1
	uniform_counter.add_id(counter_buffer)
	
	var uniform_config = RDUniform.new()
	uniform_config.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform_config.binding = 2
	uniform_config.add_id(uniform_buffer)
	
	var uniform_set = rd.uniform_set_create([uniform_output, uniform_counter, uniform_config], shader_rid, 0)
	
	# 3. Dispatch
	var pipeline = rd.compute_pipeline_create(shader_rid)
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	# Group size is 4x4x4 = 64 threads.
	var groups_x = ceil(grid_size / 4.0)
	var groups_y = ceil(grid_size / 4.0)
	var groups_z = ceil(grid_size / 4.0)
	
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, groups_z)
	rd.compute_list_end()
	
	# 4. Execute and Wait
	rd.submit()
	rd.sync() # This blocks until GPU is done (safe in this thread)
	
	# 5. Read Back Data
	var count_data = rd.buffer_get_data(counter_buffer)
	var vertex_count = count_data.decode_u32(0)
	
	print("Chunk ", chunk_coord, " vertex count: ", vertex_count)
	
	if vertex_count == 0:
		# Cleanup buffers before returning
		rd.free_rid(output_buffer)
		rd.free_rid(counter_buffer)
		rd.free_rid(uniform_buffer)
		
		_finalize_empty()
		return
		
	var total_floats = vertex_count * 3
	var vertex_bytes = rd.buffer_get_data(output_buffer, 0, total_floats * 4)
	var vertex_array = vertex_bytes.to_float32_array()
	
	# 6. Cleanup Local Resources
	rd.free_rid(output_buffer)
	rd.free_rid(counter_buffer)
	rd.free_rid(uniform_buffer)
	
	# 7. Process Data (Sync)
	var vec_verts = PackedVector3Array()
	vec_verts.resize(vertex_array.size() / 3)
	
	for i in range(0, vertex_array.size(), 3):
		vec_verts[i/3] = Vector3(vertex_array[i], vertex_array[i+1], vertex_array[i+2])
	
	# 8. Handover
	_finalize_mesh(vec_verts)

func _finalize_mesh(vec_verts: PackedVector3Array):
	if vec_verts.is_empty():
		generation_complete.emit(chunk_coord)
		return
		
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vec_verts
	
	# Auto-calculate normals
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.create_from_arrays(arrays)
	st.index() # CRITICAL: Merges vertices for smooth shading
	st.generate_normals()
	var new_mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.4, 0.2) # Brown
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	self.material_override = mat
	
	self.mesh = new_mesh
	create_trimesh_collision()
	
	generation_complete.emit(chunk_coord)

func _finalize_empty():
	generation_complete.emit(chunk_coord)
