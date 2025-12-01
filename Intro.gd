extends Control

@onready var video_player = $VideoStreamPlayer

# The scene to load after the intro
const MAIN_GAME_SCENE = "res://node_3d.tscn"

func _ready():
	# Ensure video plays and fits screen
	if video_player:
		video_player.play()
		
	# Hide mouse for cinematic feel
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _process(delta):
	# Allow skipping with any key or mouse click
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_start_game()

func _on_video_stream_player_finished():
	_start_game()

func _start_game():
	# Restore mouse mode (MainGame will handle it, but good practice)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Change to the actual game scene
	get_tree().change_scene_to_file(MAIN_GAME_SCENE)
