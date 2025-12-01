extends Node3D

# Preload resources to prevent lag spikes
const PISTOL_SOUND = preload("res://sfx/pistol-shot-233473.mp3")
# Use preload for blocks too
const BLOCK_SCENE = preload("res://Block.tscn")
const RAMP_SCENE = preload("res://Block_ramp.tscn")

# Reference to the AnimationPlayer child node
@onready var animation_player = $AnimationPlayer

# Variable to hold the dynamic audio player
var audio_player: AudioStreamPlayer3D
var current_slot: int = 0

# Ghost / Building variables
var ghost_node: Node3D = null
var block_rotation_index: int = 0 # 0 to 3, representing 0, 90, 180, 270 degrees

func _ready():
	# 1. Setup Audio
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)
	audio_player.stream = PISTOL_SOUND
	# Allow up to 5 overlapping sounds so rapid clicks don't cut off previous shots
	audio_player.max_polyphony = 5
	
	# 2. Setup Crosshair (UI)
	setup_crosshair()
	
	# 3. Connect to Toolbelt
	var toolbelt = get_node_or_null("/root/Node3D/HUDCanvasLayer/HUDToolbelt")
	if toolbelt:
		toolbelt.slot_changed.connect(_on_slot_changed)

func _process(delta):
	update_ghost_transform()

func _on_slot_changed(index):
	current_slot = index
	update_active_ghost()

func update_active_ghost():
	# Remove existing ghost
	if ghost_node:
		ghost_node.queue_free()
		ghost_node = null
	
	var scene_to_spawn = null
	if current_slot == 1:
		scene_to_spawn = BLOCK_SCENE
	elif current_slot == 2:
		scene_to_spawn = RAMP_SCENE
	
	if scene_to_spawn:
		ghost_node = scene_to_spawn.instantiate()
		get_tree().root.add_child(ghost_node)
		
		# Make it transparent and non-colliding
		prepare_ghost_node_recursive(ghost_node)
		ghost_node.visible = false # Start hidden until raycast hits

func prepare_ghost_node_recursive(node: Node):
	if node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.5, 0.8, 1.0, 0.4) # Blue-ish transparent
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	if node is CollisionShape3D or node is CollisionPolygon3D:
		node.disabled = true
	
	for child in node.get_children():
		prepare_ghost_node_recursive(child)

func update_ghost_transform():
	if not ghost_node: return
	
	# Perform raycast to find position
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var center_screen = get_viewport().get_visible_rect().size / 2
	var from = camera.project_ray_origin(center_screen)
	var to = from + camera.project_ray_normal(center_screen) * 1000 # Increased range
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	
	# Exclude the ghost itself just in case (though collision is disabled)
	# query.exclude = [ghost_node] 
	
	var result = space_state.intersect_ray(query)
	
	if result:
		ghost_node.visible = true
		var pos = result.position + result.normal * 0.5
		var snapped_pos = pos.snapped(Vector3(1, 1, 1))
		ghost_node.global_position = snapped_pos
		
		# Apply rotation
		ghost_node.global_rotation.y = deg_to_rad(block_rotation_index * 90.0)
	else:
		ghost_node.visible = false

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
			# Rotation Logic (Scroll Wheel + CTRL)
			if Input.is_key_pressed(KEY_CTRL):
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					block_rotation_index = (block_rotation_index + 1) % 4
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					block_rotation_index = (block_rotation_index - 1 + 4) % 4
			
			if event.button_index == MOUSE_BUTTON_LEFT:
				if current_slot == 1:
					place_block(BLOCK_SCENE)
				elif current_slot == 2:
					place_block(RAMP_SCENE)
				else:
					# Pistol / Tool logic
					play_animation_segment()
					if Input.is_key_pressed(KEY_SHIFT):
						fire_build("box") # Shift + Left Click to place terrain block
					elif Input.is_key_pressed(KEY_CTRL):
						fire_build("sphere") # Ctrl + Left Click to build organic
					else:
						fire_raycast() # Just Left Click to shoot

			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if current_slot == 1 or current_slot == 2:
					remove_block()
				else:
					# Pistol Logic
					if Input.is_key_pressed(KEY_CTRL):
						play_animation_segment()
						fire_dig() # Ctrl + Right Click to dig terrain
					elif Input.is_key_pressed(KEY_SHIFT):
						play_animation_segment()
						fire_road_paint(1.0)
					# else: plain Right Click is now ADS (Aim Down Sights), handled in PlayerCharacter3D.gd
					# We do NOT play the animation for ADS to keep the sight steady

func play_animation_segment():
	# Only play if pistol is active (Slot 0)
	if current_slot != 0: return

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

func place_block(scene_to_place):
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
		
		if scene_to_place:
			var block = scene_to_place.instantiate()
			get_tree().root.add_child(block)
			block.global_position = snapped_pos
			block.global_rotation.y = deg_to_rad(block_rotation_index * 90.0)

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
