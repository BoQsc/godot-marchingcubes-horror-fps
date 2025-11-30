extends Node3D

@export var chunk_scene: PackedScene # Assign ComputeChunk.tscn here
@export var player: Node3D # Assign your Player node here

@export_group("Settings")
@export var render_distance: int = 8 # Increased render distance since GPU is faster
@export var chunks_per_frame: int = 4
@export var grid_size: int = 32
@export var scale_factor: float = 1.0
@export var terrain_height: float = 30.0
@export var iso_level: float = 0.0

var active_chunks = {} # Key: Vector3, Value: Chunk Instance
var chunks_to_generate = [] # Queue for generation

var last_chunk_coord: Vector3i = Vector3i(999999, 999999, 999999) # Initialize with impossible value

const SHADER_PATH = "res://compute_version/marching_cubes.glsl"

var rd: RenderingDevice
var shader_rid: RID

func _ready():
	print("ComputeTerrainManager Ready!")
	print("Settings: Render Distance=", render_distance, ", Chunks/Frame=", chunks_per_frame)
	
	_initialize_compute_device()

func _initialize_compute_device():
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		push_error("Failed to create local RenderingDevice")
		return
		
	var shader_file = load(SHADER_PATH)
	if not shader_file:
		push_error("Failed to load shader: " + SHADER_PATH)
		return
		
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	
	if not shader_rid.is_valid():
		push_error("Failed to create shader from SPIR-V")
		var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		push_error("SPIR-V Error: " + err)

func _exit_tree():
	if rd:
		if shader_rid.is_valid():
			rd.free_rid(shader_rid)
		rd.free()

func _process(delta):
	if not player: return
	
	update_chunks()
	process_generation_queue()

func update_chunks():
	# Calculate which chunk the player is standing in
	var p_pos = player.global_position
	var chunk_world_size = grid_size * scale_factor
	
	var current_chunk_x = int(p_pos.x / chunk_world_size)
	var current_chunk_z = int(p_pos.z / chunk_world_size)
	
	# Handle negative coordinates correctly
	if p_pos.x < 0: current_chunk_x -= 1
	if p_pos.z < 0: current_chunk_z -= 1
	
	var current_coord = Vector3i(current_chunk_x, 0, current_chunk_z)
	
	# Optimization: Only update if player moved to a new chunk
	if current_coord == last_chunk_coord:
		return
	
	print("Player moved to chunk: ", current_coord)
	last_chunk_coord = current_coord
	
	# 1. Identify chunks that should exist
	var target_chunks = {} # Use Dictionary for O(1) lookups
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var offset = Vector3i(x, 0, z)
			target_chunks[current_coord + offset] = true
	
	# 2. Remove far away chunks
	var chunks_to_remove = []
	for coord in active_chunks.keys():
		if not target_chunks.has(coord):
			chunks_to_remove.append(coord)
	
	for coord in chunks_to_remove:
		if active_chunks[coord]:
			active_chunks[coord].queue_free()
		active_chunks.erase(coord)
	
	# 3. Add new chunks to queue
	var new_chunks = []
	for coord in target_chunks.keys():
		if not active_chunks.has(coord):
			new_chunks.append(coord)
			# Mark as active immediately to prevent duplicates
			active_chunks[coord] = null
	
	# Sort new chunks by distance to player so we see immediate results
	new_chunks.sort_custom(func(a, b):
		return a.distance_squared_to(current_coord) < b.distance_squared_to(current_coord)
	)
	
	chunks_to_generate.append_array(new_chunks)
	print("Added ", new_chunks.size(), " chunks to queue. Total in queue: ", chunks_to_generate.size())
	
	# Optional: Re-sort the entire queue occasionally if the player moves fast,
	# but for now, just appending sorted batches is enough. 

func process_generation_queue():
	if chunks_to_generate.is_empty(): return
	
	# Spawn multiple chunks per frame
	for i in range(chunks_per_frame):
		if chunks_to_generate.is_empty(): break
		
		var coord = chunks_to_generate.pop_front()
		
		if not chunk_scene:
			push_error("Chunk Scene not assigned in ComputeTerrainManager!")
			return

		var chunk = chunk_scene.instantiate()
		add_child(chunk)
		
		var world_pos = Vector3(
			coord.x * grid_size * scale_factor,
			0,
			coord.z * grid_size * scale_factor
		)
		chunk.global_position = world_pos
		
		# Store reference
		active_chunks[coord] = chunk
		
		# Start generation (Notice we don't pass noise object, shader handles it)
		if rd and shader_rid.is_valid():
			chunk.start_generation(coord, grid_size, iso_level, scale_factor, terrain_height, rd, shader_rid)
		else:
			push_error("Cannot start generation: RD or Shader invalid")
