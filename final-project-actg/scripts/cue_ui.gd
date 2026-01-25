extends CanvasLayer

@onready var label := $ColorRect/Label
var _open := false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS  # so it works while paused
	hide()

func show_message(text: String) -> void:
	_open = true
	label.text = text
	show()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close() -> void:
	_open = false
	hide()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if not _open:
		return

	# ESC
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return

	# Any mouse click
	if event is InputEventMouseButton and event.pressed:
		close()
		get_viewport().set_input_as_handled()
		return
