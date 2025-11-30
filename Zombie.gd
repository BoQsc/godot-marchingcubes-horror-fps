extends CharacterBody3D

# --- Settings ---
@export var max_health: int = 3
var current_health: int

# --- References ---
@onready var anim_player = $"Sketchfab_Scene zombie".find_child("AnimationPlayer")

# --- State ---
var current_state = "IDLE"
var wander_timer: float = 0.0
var attack_timer: float = 0.0 # Cooldown

# --- Movement ---
@export var move_speed: float = 1.0
@export var gravity: float = 9.8
@export var friction: float = 10.0

var skeleton: Skeleton3D

func _ready():
	current_health = max_health
	
	# Find Skeleton recursively
	skeleton = find_skeleton($"Sketchfab_Scene zombie")
	
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

func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var res = find_skeleton(child)
		if res: return res
	return null

func _physics_process(delta):
	if current_state == "DEAD":
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	# --- ANIMATION LOGIC (Restored) ---
	if anim_player:
		var t = anim_player.current_animation_position
		
		if current_state == "IDLE":
			if t >= 1.0: anim_player.seek(t - 1.0)
			
		elif current_state == "WALK" or current_state == "CHASE":
			if t >= 2.0: anim_player.seek(1.0 + (t - 2.0))
			
		elif current_state == "ATTACK":
			# Attack Slice: 3.5s to 4.5s
			if t >= 4.5: anim_player.seek(3.5 + (t - 4.5))

	# --- MOVEMENT LOGIC ---
	if current_state == "IDLE":
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)
		
		wander_timer -= delta
		if wander_timer <= 0:
			pick_random_direction()
			change_state("WALK")
			
		var player = get_node_or_null("/root/Node3D/PlayerCharacter3D")
		if player and global_position.distance_to(player.global_position) < 2.0:
			change_state("CHASE")
			
	elif current_state == "WALK":
		var forward_dir = transform.basis.z.normalized()
		velocity.x = forward_dir.x * move_speed
		velocity.z = forward_dir.z * move_speed
		
		wander_timer -= delta
		
		var wd = get_node_or_null("WallDetector")
		if (wd and wd.is_colliding()) or wander_timer <= 0:
			change_state("IDLE")
			
		var player = get_node_or_null("/root/Node3D/PlayerCharacter3D")
		if player and global_position.distance_to(player.global_position) < 2.0:
			change_state("CHASE")

	elif current_state == "CHASE":
		var player = get_node_or_null("/root/Node3D/PlayerCharacter3D")
		if player:
			var dist = global_position.distance_to(player.global_position)
			if dist > 20.0:
				change_state("IDLE")
			elif dist < 1.5:
				change_state("ATTACK")
			else:
				look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
				rotate_y(PI)
				
				var dir = (player.global_position - global_position).normalized()
				velocity.x = dir.x * (move_speed * 2.5)
				velocity.z = dir.z * (move_speed * 2.5)
	
	elif current_state == "ATTACK":
		var player = get_node_or_null("/root/Node3D/PlayerCharacter3D")
		if player:
			var dist = global_position.distance_to(player.global_position)
			if dist > 2.5:
				change_state("CHASE")
			else:
				look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
				rotate_y(PI)
				velocity = Vector3.ZERO
				
				attack_timer -= delta
				if attack_timer <= 0:
					attack(player)
					attack_timer = 1.0

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
		if new_state == "ATTACK": anim_player.seek(3.5)
		
	if new_state == "IDLE": wander_timer = randf_range(2.0, 4.0)
	if new_state == "WALK": wander_timer = randf_range(3.0, 6.0)

func pick_random_direction():
	rotate_y(deg_to_rad(randf_range(90, 270)))

func attack(player):
	# Simple attack
	print("Zombie Attacked Player!")
	if player.has_method("take_damage"):
		player.take_damage(1)

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
	
	# Disable collision
	$CollisionShape3D.disabled = true
	
	if anim_player:
		anim_player.play("Take 001")
		anim_player.seek(9.5, true) # Seek to death start
		
		# Play the death slice
		await get_tree().create_timer(0.9).timeout
		anim_player.pause() # Stop at the end frame
	
	# Disappear after a delay
	await get_tree().create_timer(3.0).timeout
	queue_free()
