extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
const WATER_LEVEL = 15.0

@onready var camera = $Camera3D

var environment: Environment
var original_fog_enabled: bool = false
var original_fog_color: Color
var original_fog_density: float

var health: int = 10
var max_health: int = 10

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Get the WorldEnvironment from the scene root
	var world_env = get_node("/root/Node3D/WorldEnvironment")
	if world_env and world_env.environment:
		environment = world_env.environment
		original_fog_enabled = environment.fog_enabled
		original_fog_color = environment.fog_light_color
		original_fog_density = environment.fog_density
		
	update_health_ui()

func take_damage(amount: int):
	health -= amount
	update_health_ui()
	
	if health <= 0:
		die()

func die():
	# Simple respawn
	get_tree().reload_current_scene()

func update_health_ui():
	var health_bar = get_node_or_null("/root/Node3D/CanvasLayer/HUDToolbelt/HealthBar")
	if health_bar:
		# Assume initial width is full health. 
		# Wait, HealthBar is a ColorRect. We can scale its x-size or pivot.
		# Or better, set its anchor_right.
		var pct = float(health) / float(max_health)
		# HealthBar was anchor_right=1.0. We can change anchor_right to pct.
		health_bar.anchor_right = pct

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	var is_underwater = global_position.y < WATER_LEVEL - 1.0 # Slight buffer
	
	if is_underwater:
		handle_swimming(delta)
		if environment:
			environment.fog_enabled = true
			environment.fog_light_color = Color(0.0, 0.1, 0.4) # Deep Blue
			environment.fog_density = 0.05 # Thick water
	else:
		handle_walking(delta)
		if environment:
			environment.fog_enabled = original_fog_enabled
			environment.fog_light_color = original_fog_color
			environment.fog_density = original_fog_density

	move_and_slide()

func handle_swimming(delta):
	# Buoyancy: Gravity is greatly reduced or reversed
	velocity.y = move_toward(velocity.y, 0.0, 0.1) # Natural drag stopping vertical movement
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Vertical Swim
	if Input.is_action_pressed("ui_accept"): # Space
		velocity.y = SPEED * 0.5
	elif Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_SHIFT):
		velocity.y = -SPEED * 0.5
	
	# Horizontal Swim (Slower)
	if direction:
		velocity.x = direction.x * (SPEED * 0.6)
		velocity.z = direction.z * (SPEED * 0.6)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * 0.1)
		velocity.z = move_toward(velocity.z, 0, SPEED * 0.1)

func handle_walking(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
