extends Control

var current_slot = 0
@onready var container = $HBoxContainer

func _ready():
	update_visuals()

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_slot = (current_slot - 1 + 9) % 9
			update_visuals()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_slot = (current_slot + 1) % 9
			update_visuals()
	
	# Supports number keys 1-9
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			current_slot = event.keycode - KEY_1
			update_visuals()

func update_visuals():
	if not container: return
	
	for i in range(container.get_child_count()):
		var slot = container.get_child(i)
		var border = slot.get_node_or_null("Border")
		
		if i == current_slot:
			slot.color = Color(0.3, 0.3, 0.3, 0.9) # Light up active slot
			if border: border.visible = true
		else:
			slot.color = Color(0.1, 0.1, 0.1, 0.6) # Dim inactive slots
			if border: border.visible = false
