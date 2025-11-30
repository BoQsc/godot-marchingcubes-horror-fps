extends Node3D

# Preload resources to prevent lag spikes
const PISTOL_SOUND = preload("res://sfx/pistol-shot-233473.mp3")
# Use preload for blocks too
const BLOCK_SCENE = preload("res://Block.tscn")

# Reference to the AnimationPlayer child node
@onready var animation_player = $AnimationPlayer

# Variable to hold the dynamic audio player
var audio_player: AudioStreamPlayer3D

func _ready():
	# 1. Setup Audio
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)
	audio_player.stream = PISTOL_SOUND
	# Allow up to 5 overlapping sounds so rapid clicks don't cut off previous shots
	audio_player.max_polyphony = 5
	
	# 2. Setup Crosshair (UI)
	setup_crosshair()

func setup_crosshair():
	# Create a canvas layer so the UI sits above the 3D world
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	# Create a container to center the crosshair
	var center_cont = CenterContainer.new()
	center_cont.set_anchors_preset(Control.PRESET_FULL_RECT) # Fill screen
	center_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(center_cont)
	
	# Create the actual crosshair dot
	var dot = ColorRect.new()
	dot.custom_minimum_size = Vector2(4, 4) # 4x4 pixel square
	dot.color = Color(1, 0, 0, 0.8) # Red with slight transparency
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_cont.add_child(dot)

func _input(event):
	# SAFETY CHECK: Do not shoot if mouse is visible (Menu is open)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		return

	# Check if the event is a Mouse Button event
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if Input.is_key_pressed(KEY_ALT):
					play_animation_segment()
					place_block() # Alt + Left Click to place object
				elif Input.is_key_pressed(KEY_SHIFT):
					play_animation_segment()
					fire_build("box") # Shift + Left Click to place terrain block
				elif Input.is_key_pressed(KEY_CTRL):
					play_animation_segment()
					fire_build("sphere") # Ctrl + Left Click to build organic
				else:
					play_animation_segment()
					fire_raycast() # Just Left Click to shoot
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				play_animation_segment()
				if Input.is_key_pressed(KEY_ALT):
					remove_block() # Alt + Right Click to remove object
				elif Input.is_key_pressed(KEY_CTRL):
					fire_dig() # Ctrl + Right Click to dig terrain
				elif Input.is_key_pressed(KEY_SHIFT):
					fire_road_paint(1.0)
				# else: plain Right Click does nothing, freeing it up

func play_animation_segment():
	# check if the animation exists to avoid errors
	if animation_player and animation_player.has_animation("allanims"):
		animation_player.stop()
		
		audio_player.play()
		animation_player.play("allanims")
		
		# Create a temporary timer for 0.3 seconds and wait for it to finish
		await get_tree().create_timer(0.3).timeout
		
		# SAFETY CHECK: Ensure the node and player still exist after the wait
		if is_instance_valid(animation_player):
			animation_player.stop()

# Helper to find TerrainManager even if path changes
func get_terrain_manager():
	if has_node("/root/Node3D/TerrainManager"):
		return get_node("/root/Node3D/TerrainManager")
	return null

func fire_road_paint(amount):
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var center_screen = get_viewport().get_visible_rect().size / 2
	var from = camera.project_ray_origin(center_screen)
	var to = from + camera.project_ray_normal(center_screen) * 1000
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var tm = get_terrain_manager()
		if tm:
			tm.modify_road(result.position, amount, 4.0)
		
		spawn_hit_effect(result.position)

func fire_raycast():
	var camera = get_viewport().get_camera_3d()
	if not camera: return

	var center_screen = get_viewport().get_visible_rect().size / 2
	var from = camera.project_ray_origin(center_screen)
	var to = from + camera.project_ray_normal(center_screen) * 1000
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		if result.collider.is_in_group("blocks") and result.collider.has_method("take_damage"):
			result.collider.take_damage(1)
		else:
			# Micro-digging on terrain
			var tm = get_terrain_manager()
			if tm:
				tm.modify_terrain(result.position, 2.0, "sphere", 0.5)
		
		spawn_hit_effect(result.position)

func spawn_hit_effect(pos):
	# Create a small red sphere to represent the bullet hole/spark
	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	
	# Create a bright red material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mat.emission_enabled = true
	mat.emission = Color.RED
	mat.emission_energy_multiplier = 2.0
	
	mesh_instance.mesh = sphere
	mesh_instance.material_override = mat
	
	# Add to the scene root so it stays in place in the world
	get_tree().root.add_child(mesh_instance)
	mesh_instance.global_position = pos
	
	# Destroy the effect after 2 seconds
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(mesh_instance):
		mesh_instance.queue_free()

func fire_dig():
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var center_screen = get_viewport().get_visible_rect().size / 2
	var from = camera.project_ray_origin(center_screen)
	var to = from + camera.project_ray_normal(center_screen) * 1000
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var tm = get_terrain_manager()
		if tm:
			# Digging: Add positive value (Air)
			tm.modify_terrain(result.position, 5.0, "sphere")
		
		spawn_hit_effect(result.position)

func fire_build(shape="sphere"):
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var center_screen = get_viewport().get_visible_rect().size / 2
	var from = camera.project_ray_origin(center_screen)
	var to = from + camera.project_ray_normal(center_screen) * 1000
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var tm = get_terrain_manager()
		if tm:
			# Building: Subtract negative value (add matter)
			tm.modify_terrain(result.position, -5.0, shape)
		
		spawn_build_effect(result.position)

func spawn_build_effect(pos):
	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5 # Increased size to be visible
	sphere.height = 1.0
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 1, 0, 0.5) # Green ghost effect
	
	mesh_instance.mesh = sphere
	mesh_instance.material_override = mat
	
	# FIX: Added add_child so the mesh actually appears
	get_tree().root.add_child(mesh_instance)
	mesh_instance.global_position = pos

func place_block():
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var center_screen = get_viewport().get_visible_rect().size / 2
	var from = camera.project_ray_origin(center_screen)
	var to = from + camera.project_ray_normal(center_screen) * 1000
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var pos = result.position + result.normal * 0.5
		var snapped_pos = pos.snapped(Vector3(1, 1, 1))
		
		if BLOCK_SCENE:
			var block = BLOCK_SCENE.instantiate()
			get_tree().root.add_child(block)
			block.global_position = snapped_pos

func remove_block():
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var center_screen = get_viewport().get_visible_rect().size / 2
	var from = camera.project_ray_origin(center_screen)
	var to = from + camera.project_ray_normal(center_screen) * 1000
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider:
		if result.collider.is_in_group("blocks"):
			result.collider.queue_free()
			spawn_hit_effect(result.position) # Visual feedback
