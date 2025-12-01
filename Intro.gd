extends Control

@onready var video_player = $VideoStreamPlayer

# The scene to load after the intro
const MAIN_GAME_SCENE = "res://node_3d.tscn"
const LOADING_VIDEO = preload("res://video/Video_Generation_CPU_Terrain_Loading.ogv")

var time_elapsed: float = 0.0
var second_video_triggered: bool = false

func _ready():
	# Ensure video plays and fits screen
	if video_player:
		video_player.play()
		
	# Hide mouse for cinematic feel
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _process(delta):
	time_elapsed += delta
	
	# Interrupt after 10 seconds
	if not second_video_triggered and time_elapsed >= 10.0:
		second_video_triggered = true
		if video_player:
			video_player.stream = LOADING_VIDEO
			video_player.play()
	
	# Allow skipping with any key or mouse click
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_start_game()

func _on_video_stream_player_finished():
	# Only start game if the second video finished (or if we skipped)
	# If the first video finishes naturally before 3s (short intro), we just go to game? 
	# Or we force the second video? 
	# The prompt says "make reappearance", implying it SHOULD be seen.
	# If the first video is shorter than 3s, this signal fires.
	# Let's assume we want to show the second video regardless.
	
	if not second_video_triggered:
		second_video_triggered = true
		video_player.stream = LOADING_VIDEO
		video_player.play()
	else:
		_start_game()

func _start_game():
	# Restore mouse mode (MainGame will handle it, but good practice)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Change to the actual game scene
	get_tree().change_scene_to_file(MAIN_GAME_SCENE)
