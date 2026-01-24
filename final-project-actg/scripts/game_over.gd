extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _on_try_again_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/test_level.tscn")


func _on_give_up_pressed() -> void:
	get_tree().quit()
