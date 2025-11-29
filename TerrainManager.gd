extends Node3D

@export var chunk_scene: PackedScene # Assign MarchingCubesChunk.tscn here
@export var player: Node3D # Assign your Player node here

@export_group("Settings")
@export var render_distance: int = 8 # Increased default
@export var chunks_per_frame: int = 8 # Process multiple chunks per frame
@export var grid_size: int = 32
@export var scale_factor: float = 1.0
@export var terrain_height: float = 30.0

var noise = FastNoiseLite.new()
var active_chunks = {} # Key: Vector3i, Value: Chunk Instance
var chunks_in_queue = {} # Key: Vector3i, Value: true (Fast lookup)
var chunks_to_generate = [] # Array of Vector3i for ordering

func _ready():
	noise.seed = randi()
	noise.frequency = 0.02
	noise.noise_type = FastNoiseLite.TYPE_PERLIN

func _process(delta):
	if not player: return
	
	update_chunks()
	process_generation_queue()

func update_chunks():
	var p_pos = player.global_position
	var chunk_world_size = grid_size * scale_factor
	
	var current_chunk_x = int(floor(p_pos.x / chunk_world_size))
	var current_chunk_z = int(floor(p_pos.z / chunk_world_size))
	var current_coord = Vector3i(current_chunk_x, 0, current_chunk_z)
	
	# 1. Identify chunks that should exist
	var target_chunks = {}
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
		if not active_chunks.has(coord) and not chunks_in_queue.has(coord):
			new_chunks.append(coord)
			chunks_in_queue[coord] = true
	
	if new_chunks.is_empty(): return

	# Sort by distance to player (nearest first)
	new_chunks.sort_custom(func(a, b):
		return a.distance_squared_to(current_coord) < b.distance_squared_to(current_coord)
	)
	
	chunks_to_generate.append_array(new_chunks)

func process_generation_queue():
	if chunks_to_generate.is_empty(): return
	
	for i in range(chunks_per_frame):
		if chunks_to_generate.is_empty(): break
		
		var coord = chunks_to_generate.pop_front()
		chunks_in_queue.erase(coord) # Remove from queue lookup
		
		if active_chunks.has(coord): continue # Should not happen but safety check
		
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
		
		# Start generation
		chunk.start_generation(coord, grid_size, 0.0, scale_factor, terrain_height, noise)
