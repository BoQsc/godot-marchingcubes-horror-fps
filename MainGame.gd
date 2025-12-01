extends Node3D

@onready var player = $PlayerCharacter3D
@onready var terrain_manager = $TerrainManager
@onready var loading_screen = $LoadingLayer

func _ready():
	# Start in Loading State
	if loading_screen:
		loading_screen.visible = true
	
	# Disable player movement/input
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Ensure cursor is visible during loading (overriding Player's _ready)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Listen for terrain completion
	if terrain_manager:
		terrain_manager.initial_generation_finished.connect(_on_terrain_ready)

func _on_terrain_ready():
	print("Terrain Ready!")
	
	# Hide Loading Screen
	if loading_screen:
		loading_screen.visible = false
		# Optional: Queue free if you never want it back
		# loading_screen.queue_free()
	
	# Enable Player
	if player:
		player.process_mode = Node.PROCESS_MODE_INHERIT
		
	# Capture Mouse for Gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
