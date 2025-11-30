extends Control

func _ready():
	# Start hidden (Game mode)
	visible = false
	
	# Connect the button signal manually since it is a dynamic child
	var btn = get_node_or_null("ExitButton")
	if btn:
		btn.pressed.connect(_on_exit_pressed)

func _input(event):
	# Toggle Menu on ESC
	if event.is_action_pressed("ui_cancel"):
		visible = not visible
		
		if visible:
			# Menu Mode: Show mouse
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			# Game Mode: Capture mouse
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			
		# STOP the input from going to other scripts
		get_viewport().set_input_as_handled()

func _on_exit_pressed():
	get_tree().quit()
