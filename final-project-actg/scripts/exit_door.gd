# ExitDoor.gd
extends Area3D

@export var completed_scene_path: String = "res://scenes/game_completed.tscn"

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D:
		AudioManager.stop_all_audio_for_win()
		await get_tree().process_frame
		get_tree().change_scene_to_file("res://scenes/game_completed.tscn")
