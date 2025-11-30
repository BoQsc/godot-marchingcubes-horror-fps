@tool
extends Camera3D

const MOUSE_SENSITIVITY = 0.002

func _get_configuration_warnings():
	var warnings = []
	
	if not get_parent() is CharacterBody3D:
		warnings.append("Requires CharacterBody3D as a parent of Camera3D")
	
	return warnings

func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED and Engine.is_editor_hint():
		call_deferred("update_configuration_warnings")

func _ready() -> void:
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	
	# Capture the mouse cursor for first-person controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
		
	# Handle mouse look ONLY if captured
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate parent horizontally (yaw)
		get_parent().rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		
		# Rotate camera vertically (pitch)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * MOUSE_SENSITIVITY)
		
		# Clamp vertical rotation to prevent flipping
		rotation.x = clamp(rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
		
	# Mouse Capture Logic
	# This only runs if the UI didn't catch the click.
	# So if Menu is open (STOP filter), this won't run.
	# If Menu is closed, this catches clicks on the world to recapture mouse.
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
