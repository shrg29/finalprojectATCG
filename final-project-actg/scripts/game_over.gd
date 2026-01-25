extends Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	AudioManager.stop_all_audio_for_win()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_try_again_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_scene.tscn")

func _on_give_up_pressed() -> void:
	get_tree().quit()
