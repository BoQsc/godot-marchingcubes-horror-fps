extends AudioStreamPlayer3D

# --- CONFIGURATION ---
@export var step_interval: float = 0.5
@export var sound_files: Array[AudioStream] = [
	preload("res://sfx/st1-footstep-sfx-323053.mp3"),
	preload("res://sfx/st2-footstep-sfx-323055.mp3"),
	preload("res://sfx/st3-footstep-sfx-323056.mp3")
]

# Internal variables
var timer: float = 0.0
var parent_player: CharacterBody3D

func _ready():
	# 1. Get the parent node (The Player)
	parent_player = get_parent()
	
	# Safety check: Ensure parent is actually a CharacterBody3D
	if not parent_player is CharacterBody3D:
		set_physics_process(false)
		printerr("FootstepComponent must be a child of a CharacterBody3D!")

func _physics_process(delta):
	# 2. Monitor the parent's state
	
	# We only care about horizontal speed (ignoring gravity/falling speed)
	var horizontal_velocity = Vector2(parent_player.velocity.x, parent_player.velocity.z)
	
	# Check: Is parent on floor? Is parent moving?
	if parent_player.is_on_floor() and horizontal_velocity.length() > 0.1:
		timer -= delta
		if timer <= 0:
			_play_random_sound()
			timer = step_interval
	else:
		# Reset timer so step plays immediately when movement starts
		timer = 0.0

func _play_random_sound():
	if sound_files.is_empty(): return
	
	stream = sound_files.pick_random()
	pitch_scale = randf_range(0.9, 1.1)
	play()
