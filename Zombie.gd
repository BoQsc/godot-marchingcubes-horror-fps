extends CharacterBody3D

# --- Settings ---
@export var max_health: int = 3
var current_health: int

# --- References ---
@onready var anim_player = $"Sketchfab_Scene zombie".find_child("AnimationPlayer")

# --- State ---
var current_state = "IDLE"
var wander_timer: float = 0.0

# --- Movement ---
@export var move_speed: float = 1.0
@export var gravity: float = 9.8
@export var friction: float = 10.0

func _ready():
	current_health = max_health
	
	# Setup Wall Detector
	var wall_detector = RayCast3D.new()
	wall_detector.name = "WallDetector"
	add_child(wall_detector)
	wall_detector.position = Vector3(0, 1.0, 0.6)
	wall_detector.enabled = true
	wall_detector.target_position = Vector3(0, 0, 1.0)

	if anim_player:
		if anim_player.has_animation("Take 001"):
			anim_player.play("Take 001")
			anim_player.get_animation("Take 001").loop_mode = Animation.LOOP_NONE
		anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

	# Safety Start
	set_physics_process(false)
	await get_tree().create_timer(0.5).timeout
	set_physics_process(true)
	change_state("IDLE")

func _physics_process(delta):
	if current_state == "DEAD":
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	# Animation Loop Logic
	if anim_player:
		var t = anim_player.current_animation_position
		if current_state == "IDLE":
			if t >= 1.0: anim_player.seek(t - 1.0)
		elif current_state == "WALK":
			if t >= 2.0: anim_player.seek(1.0 + (t - 2.0))

	# Movement Logic
	if current_state == "IDLE":
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)
		
		wander_timer -= delta
		if wander_timer <= 0:
			pick_random_direction()
			change_state("WALK")
			
	elif current_state == "WALK":
		var forward_dir = transform.basis.z.normalized()
		velocity.x = forward_dir.x * move_speed
		velocity.z = forward_dir.z * move_speed
		
		wander_timer -= delta
		
		var wd = get_node_or_null("WallDetector")
		if (wd and wd.is_colliding()) or wander_timer <= 0:
			change_state("IDLE")

	move_and_slide()
	
	# Void Safety
	if global_position.y < -50:
		velocity = Vector3.ZERO
		global_position = Vector3(0, 5, 0)

func change_state(new_state):
	if current_state == "DEAD": return
	current_state = new_state
	
	if anim_player:
		if new_state == "IDLE": anim_player.seek(0.0)
		if new_state == "WALK": anim_player.seek(1.0)
		
	if new_state == "IDLE": wander_timer = randf_range(2.0, 4.0)
	if new_state == "WALK": wander_timer = randf_range(3.0, 6.0)

func pick_random_direction():
	rotate_y(deg_to_rad(randf_range(90, 270)))

# --- DAMAGE SYSTEM ---
func take_damage(amount: int):
	if current_state == "DEAD": return
	
	current_health -= amount
	print("Zombie took damage! HP: ", current_health)
	
	# Flash red effect (optional visual feedback)
	# spawn_blood_effect() 
	
	if current_health <= 0:
		die()

func die():
	current_state = "DEAD"
	print("Zombie Died!")
	velocity = Vector3.ZERO
	
	# Play death animation if available, or just fall over
	# For now, let's just disable collision and fade out
	$CollisionShape3D.disabled = true
	
	# Simple "fall over" tween
	var tween = create_tween()
	tween.tween_property(self, "rotation:x", deg_to_rad(-90), 0.5)
	# Remove invalid modulate tween
	tween.tween_callback(queue_free).set_delay(2.0)
