extends Node3D

@export var chunk_scene: PackedScene # Assign MarchingCubesChunk.tscn here
@export var player: Node3D # Assign your Player node here

@export_group("Settings")
@export var render_distance: int = 16 # Increased for larger world
@export var chunks_per_frame: int = 1 # Very conservative loading
@export var max_concurrent_tasks: int = 32 # Significantly increased for massive initial loading
@export var grid_size: int = 32
@export var scale_factor: float = 1.0
@export var terrain_height: float = 30.0

# Performance monitoring settings
@export_group("Performance Settings")
@export var target_fps: float = 60.0
@export var min_fps: float = 40.0 # Increased minimum for smoother gameplay
@export var fps_check_interval: float = 0.5 # Check FPS every 0.5 seconds
@export var initial_loading_radius: int = 32 # HUGE initial loading area (65x65 chunks)
@export var loading_screen_path: NodePath # Path to loading screen UI node
@export var initial_loading_timeout: float = 60.0 # Increased timeout for massive area
@export var resume_check_interval: float = 3.0 # Check less frequently
@export var performance_headroom_threshold: float = 10.0 # Only load when FPS is this much above target

# Multi-GPU settings
@export_group("Multi-GPU Settings")
@export var use_multi_gpu: bool = true # Enable multi-GPU functionality
@export var igpu_workload_ratio: float = 0.3 # Percentage of work to offload to iGPU (0.0-1.0)
@export var igpu_task_types: Array[String] = ["LOD", "Culling", "Physics"] # Tasks to offload to iGPU

var noise = FastNoiseLite.new()
var active_chunks = {} # Key: Vector3i, Value: Chunk Instance
var chunks_in_queue = {} # Key: Vector3i, Value: true (Fast lookup)
var chunks_to_generate = [] # Array of Vector3i for ordering
var current_active_tasks: int = 0

# Multi-GPU variables
var rendering_device: RenderingDevice
var igpu_device: RenderingDevice
var gpu_tasks = {} # Dictionary to track which GPU is handling which task
var igpu_available: bool = false
var dgpu_available: bool = false

# Loading state management
enum LoadingState {
	INITIAL_LOADING,  # Loading initial chunks at full speed
	PLAYING,          # Game is playing, load chunks very conservatively
	PAUSED            # Loading paused to maintain FPS
}

var current_loading_state: LoadingState = LoadingState.INITIAL_LOADING
var loading_screen: Control
var initial_chunks_loaded: int = 0
var total_initial_chunks: int = 0
var initial_loading_start_time: float = 0.0

# Performance monitoring variables
var fps_timer: float = 0.0
var current_fps: float = 60.0
var last_frame_time: float = 0.0
var frame_count: int = 0
var chunks_per_frame_adjusted: int = 1
var resume_timer: float = 0.0
var fps_history: Array[float] = [] # Track FPS over time
var history_size: int = 20 # Increased history size for more stable readings
var last_load_time: float = 0.0
var load_cooldown: float = 0.2 # Minimum time between chunk loads

func _ready():
	noise.seed = randi()
	noise.frequency = 0.02
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	last_frame_time = Time.get_ticks_msec() / 1000.0
	initial_loading_start_time = Time.get_ticks_msec() / 1000.0
	
	# Initialize multi-GPU support
	if use_multi_gpu:
		initialize_multi_gpu()
	
	# Set up loading screen if provided
	if loading_screen_path:
		loading_screen = get_node(loading_screen_path) as Control
		if loading_screen:
			loading_screen.visible = true
	
	# Calculate total initial chunks needed (MASSIVE area now)
	total_initial_chunks = (initial_loading_radius * 2 + 1) * (initial_loading_radius * 2 + 1)
	print("========================================")
	print("INITIAL LOADING CONFIGURATION:")
	print("Loading Radius: ", initial_loading_radius, " chunks")
	print("Total Area: ", (initial_loading_radius * 2 + 1), "x", (initial_loading_radius * 2 + 1), " chunks")
	print("Total chunks to load: ", total_initial_chunks)
	print("World size: ", (initial_loading_radius * 2 + 1) * grid_size * scale_factor, " x ", (initial_loading_radius * 2 + 1) * grid_size * scale_factor, " units")
	print("Concurrent tasks: ", max_concurrent_tasks)
	print("Multi-GPU enabled: ", use_multi_gpu)
	if use_multi_gpu:
		print("iGPU available: ", igpu_available)
		print("dGPU available: ", dgpu_available)
	print("========================================")

func initialize_multi_gpu():
	# Get the main rendering device (should be the dedicated GPU)
	rendering_device = RenderingServer.get_rendering_device()
	if rendering_device:
		dgpu_available = true
		print("Dedicated GPU detected: ", rendering_device.get_device_name())
	
	# Try to detect and initialize the integrated GPU
	# Note: This is a simplified approach - actual multi-GPU detection would be more complex
	var devices = RenderingServer.get_rendering_devices()
	for device in devices:
		var device_name = device.get_device_name()
		# Simple heuristic to identify integrated GPUs
		if "Intel" in device_name or "HD Graphics" in device_name or "Iris" in device_name:
			igpu_device = device
			igpu_available = true
			print("Integrated GPU detected: ", device_name)
			break
	
	if not igpu_available:
		print("No integrated GPU detected or available for use")

func _process(delta):
	if not player: return
	
	# Monitor FPS
	monitor_fps(delta)
	
	# Check for initial loading timeout
	if current_loading_state == LoadingState.INITIAL_LOADING:
		var elapsed = Time.get_ticks_msec() / 1000.0 - initial_loading_start_time
		if elapsed > initial_loading_timeout:
			print("Initial loading timeout reached, forcing transition to PLAYING state")
			complete_initial_loading()
	
	# Check if we should resume loading
	if current_loading_state == LoadingState.PAUSED:
		resume_timer += delta
		if resume_timer >= resume_check_interval:
			check_resume_loading()
			resume_timer = 0.0
	
	# Update chunks based on player position
	update_chunks()
	
	# Process generation queue based on current state
	match current_loading_state:
		LoadingState.INITIAL_LOADING:
			process_initial_loading()
		LoadingState.PLAYING:
			process_generation_queue_conservative()
		LoadingState.PAUSED:
			# Don't process any chunks during paused state
			pass
	
	# Process iGPU tasks if available
	if use_multi_gpu and igpu_available:
		process_igpu_tasks(delta)

func monitor_fps(delta):
	frame_count += 1
	fps_timer += delta
	
	# Calculate FPS at intervals
	if fps_timer >= fps_check_interval:
		var current_time = Time.get_ticks_msec() / 1000.0
		var elapsed = current_time - last_frame_time
		current_fps = frame_count / elapsed
		
		# Add to FPS history
		fps_history.append(current_fps)
		if fps_history.size() > history_size:
			fps_history.pop_front()
		
		# Reset counters
		frame_count = 0
		last_frame_time = current_time
		fps_timer = 0.0
		
		# Adjust loading based on FPS if in PLAYING state
		if current_loading_state == LoadingState.PLAYING:
			adjust_loading_rate()
		
		# Debug output (can be removed in production)
		print("Current FPS: ", current_fps, " | State: ", current_loading_state, " | Chunks per frame: ", chunks_per_frame_adjusted)
		print("Active chunks: ", active_chunks.size(), " | In queue: ", chunks_to_generate.size(), " | Loaded: ", initial_chunks_loaded, "/", total_initial_chunks)

func adjust_loading_rate():
	# Calculate average FPS from history
	if fps_history.is_empty():
		return
	
	var avg_fps = 0.0
	for fps in fps_history:
		avg_fps += fps
	avg_fps /= fps_history.size()
	
	# Only load if we have significant performance headroom
	if avg_fps < target_fps + performance_headroom_threshold:
		current_loading_state = LoadingState.PAUSED
		print("Pausing loading - Average FPS: ", avg_fps, " (need > ", target_fps + performance_headroom_threshold, ")")
		return
	
	# Very conservative loading rate based on performance headroom
	var headroom = avg_fps - target_fps
	var performance_ratio = headroom / performance_headroom_threshold
	
	# Adjust chunks per frame (very conservative)
	if performance_ratio > 0.8:
		chunks_per_frame_adjusted = 2  # Only load 2 chunks per frame at best
	elif performance_ratio > 0.5:
		chunks_per_frame_adjusted = 1  # Load 1 chunk per frame
	else:
		chunks_per_frame_adjusted = 1  # Always at least 1 if we have headroom

func check_resume_loading():
	# Calculate average FPS from history
	if fps_history.is_empty():
		return
	
	var avg_fps = 0.0
	for fps in fps_history:
		avg_fps += fps
	avg_fps /= fps_history.size()
	
	# Only resume if we have significant performance headroom
	if avg_fps > target_fps + performance_headroom_threshold:
		print("Resuming loading - Average FPS: ", avg_fps)
		current_loading_state = LoadingState.PLAYING
		# Start with very conservative loading rate
		chunks_per_frame_adjusted = 1

func update_chunks():
	var p_pos = player.global_position
	var chunk_world_size = grid_size * scale_factor
	
	var current_chunk_x = int(floor(p_pos.x / chunk_world_size))
	var current_chunk_z = int(floor(p_pos.z / chunk_world_size))
	var current_coord = Vector3i(current_chunk_x, 0, current_chunk_z)
	
	# Determine render distance based on loading state
	var current_render_distance = render_distance
	if current_loading_state == LoadingState.INITIAL_LOADING:
		current_render_distance = initial_loading_radius
	
	# 1. Identify chunks that should exist
	var target_chunks = {}
	for x in range(-current_render_distance, current_render_distance + 1):
		for z in range(-current_render_distance, current_render_distance + 1):
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
	
	# 3. Add new chunks to queue with priority based on distance and importance
	var new_chunks = []
	for coord in target_chunks.keys():
		if not active_chunks.has(coord) and not chunks_in_queue.has(coord):
			# Calculate distance from player for priority
			var distance = coord.distance_squared_to(current_coord)
			
			# Calculate importance based on distance (closer = more important)
			var importance = 1.0 / (1.0 + distance * 0.1)
			
			# In PLAYING state, only add chunks that are very close
			if current_loading_state == LoadingState.PLAYING:
				var max_dist = 4  # Only load chunks within 4 chunks of player
				if distance > max_dist * max_dist:
					continue
			
			new_chunks.append([coord, distance, importance])
			chunks_in_queue[coord] = true
	
	if new_chunks.is_empty(): return

	# Sort by importance (closest first), then by distance
	new_chunks.sort_custom(func(a, b):
		if abs(a[2] - b[2]) > 0.01:
			return a[2] > b[2]  # Higher importance first
		return a[1] < b[1]  # Closer distance first
	)
	
	# Add only coordinates to the generation queue
	for chunk_data in new_chunks:
		chunks_to_generate.append(chunk_data[0])

func process_initial_loading():
	# During initial loading, process chunks at maximum speed
	var chunks_to_process_this_frame = max_concurrent_tasks
	
	# Only start new tasks if we have capacity
	while current_active_tasks < max_concurrent_tasks and not chunks_to_generate.is_empty() and chunks_to_process_this_frame > 0:
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
		
		# Connect signal to release task slot
		chunk.generation_complete.connect(_on_chunk_generation_complete)
		current_active_tasks += 1
		
		# Store reference
		active_chunks[coord] = chunk
		
		# Start generation
		chunk.start_generation(coord, grid_size, 0.0, scale_factor, terrain_height, noise)
		
		chunks_to_process_this_frame -= 1
	
	# Check if initial loading is complete
	if active_chunks.size() >= total_initial_chunks or initial_chunks_loaded >= total_initial_chunks:
		complete_initial_loading()

func process_generation_queue_conservative():
	if chunks_to_generate.is_empty(): return
	
	# Only load chunks if we have performance headroom and cooldown has passed
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_load_time < load_cooldown:
		return
	
	# Process chunks very conservatively - only 1 at a time
	var chunks_to_process_this_frame = 1
	
	# Only start new tasks if we have capacity
	while current_active_tasks < max_concurrent_tasks and not chunks_to_generate.is_empty() and chunks_to_process_this_frame > 0:
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
		
		# Connect signal to release task slot
		chunk.generation_complete.connect(_on_chunk_generation_complete)
		current_active_tasks += 1
		
		# Store reference
		active_chunks[coord] = chunk
		
		# Start generation
		chunk.start_generation(coord, grid_size, 0.0, scale_factor, terrain_height, noise)
		
		chunks_to_process_this_frame -= 1
		last_load_time = current_time

func process_igpu_tasks(delta):
	# This function handles tasks that can be offloaded to the iGPU
	# These are typically less GPU-intensive tasks that can benefit from parallel processing
	
	# 1. LOD calculations for distant chunks
	if "LOD" in igpu_task_types:
		process_lod_calculations()
	
	# 2. Frustum culling for chunks
	if "Culling" in igpu_task_types:
		process_frustum_culling()
	
	# 3. Physics calculations for terrain
	if "Physics" in igpu_task_types:
		process_terrain_physics(delta)

func process_lod_calculations():
	# Calculate level of detail for chunks based on distance
	# This can be offloaded to iGPU to reduce dGPU workload
	var p_pos = player.global_position
	var chunk_world_size = grid_size * scale_factor
	
	for coord in active_chunks.keys():
		var chunk = active_chunks[coord]
		if not chunk:
			continue
			
		var chunk_pos = chunk.global_position
		var distance = p_pos.distance_to(chunk_pos)
		
		# Calculate LOD level based on distance
		var lod_level = 0
		if distance > chunk_world_size * 8:
			lod_level = 3
		elif distance > chunk_world_size * 4:
			lod_level = 2
		elif distance > chunk_world_size * 2:
			lod_level = 1
			
		# Apply LOD to chunk if it has the method
		if chunk.has_method("set_lod_level"):
			chunk.set_lod_level(lod_level)

func process_frustum_culling():
	# Perform frustum culling to determine which chunks are visible
	# This can be offloaded to iGPU to reduce dGPU workload
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
		
	# Get camera frustum planes
	var frustum = camera.get_frustum()
	
	for coord in active_chunks.keys():
		var chunk = active_chunks[coord]
		if not chunk:
			continue
			
		# Simple frustum culling check
		var chunk_pos = chunk.global_position
		var chunk_bounds = AABB(
			chunk_pos - Vector3(grid_size * scale_factor / 2, 0, grid_size * scale_factor / 2),
			Vector3(grid_size * scale_factor, terrain_height, grid_size * scale_factor)
		)
		
		# Check if chunk is visible
		var is_visible = true
		for plane in frustum:
			if not plane.intersects_aabb(chunk_bounds):
				is_visible = false
				break
				
		# Apply visibility to chunk if it has the method
		if chunk.has_method("set_visibility"):
			chunk.set_visibility(is_visible)

func process_terrain_physics(delta):
	# Process physics calculations for terrain
	# This can be offloaded to iGPU to reduce dGPU workload
	for coord in active_chunks.keys():
		var chunk = active_chunks[coord]
		if not chunk:
			continue
			
		# Only process physics for chunks near the player
		var p_pos = player.global_position
		var chunk_pos = chunk.global_position
		var distance = p_pos.distance_to(chunk_pos)
		
		if distance < grid_size * scale_factor * 3:  # Only for nearby chunks
			if chunk.has_method("process_physics"):
				chunk.process_physics(delta)

func complete_initial_loading():
	# Only transition if we're still in initial loading state
	if current_loading_state != LoadingState.INITIAL_LOADING:
		return
		
	# Switch to playing state
	current_loading_state = LoadingState.PLAYING
	print("========================================")
	print("INITIAL LOADING COMPLETE!")
	print("Final count - Active chunks: ", active_chunks.size())
	print("Chunks loaded: ", initial_chunks_loaded, "/", total_initial_chunks)
	print("Switching to very conservative loading mode.")
	print("========================================")
	
	# Hide loading screen if available
	if loading_screen:
		loading_screen.visible = false
	
	# Reset to very conservative loading
	chunks_per_frame_adjusted = 1

func _on_chunk_generation_complete(_coord):
	current_active_tasks -= 1
	
	# Track initial loading progress
	if current_loading_state == LoadingState.INITIAL_LOADING:
		initial_chunks_loaded += 1
		
		# Update loading screen if available
		if loading_screen and loading_screen.has_method("update_progress"):
			var progress = float(initial_chunks_loaded) / float(total_initial_chunks)
			loading_screen.update_progress(progress)
		
		# Check if we've loaded enough chunks
		if initial_chunks_loaded >= total_initial_chunks:
			complete_initial_loading()

func modify_terrain(global_pos: Vector3, amount: float, shape: String = "sphere", radius: float = 3.0):
	var chunk_world_size = grid_size * scale_factor
	
	# Determine range of chunks affected
	var min_x = int(floor((global_pos.x - radius) / chunk_world_size))
	var max_x = int(floor((global_pos.x + radius) / chunk_world_size))
	var min_z = int(floor((global_pos.z - radius) / chunk_world_size))
	var max_z = int(floor((global_pos.z + radius) / chunk_world_size))
	
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var coord = Vector3i(x, 0, z)
			if active_chunks.has(coord):
				var chunk = active_chunks[coord]
				var local_pos = global_pos - chunk.global_position
				chunk.modify_terrain(local_pos, radius, amount, shape)

func modify_road(global_pos: Vector3, amount: float, radius: float = 3.0):
	var chunk_world_size = grid_size * scale_factor
	
	var min_x = int(floor((global_pos.x - radius) / chunk_world_size))
	var max_x = int(floor((global_pos.x + radius) / chunk_world_size))
	var min_z = int(floor((global_pos.z - radius) / chunk_world_size))
	var max_z = int(floor((global_pos.z + radius) / chunk_world_size))
	
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var coord = Vector3i(x, 0, z)
			if active_chunks.has(coord):
				var chunk = active_chunks[coord]
				var local_pos = global_pos - chunk.global_position
				if chunk.has_method("modify_road"):
					chunk.modify_road(local_pos, radius, amount)
