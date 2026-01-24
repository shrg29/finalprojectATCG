extends Control

@onready var start_button = $CenterContainer/VBoxContainer/Start
@onready var instr_button = $CenterContainer/VBoxContainer/Instructions
@onready var quit_button = $CenterContainer/VBoxContainer/Quit
@onready var center_container = $CenterContainer
@onready var instructions_panel = $InstructionsPanel
@onready var title = $Label

func _ready():
	center_container.visible = true
	instructions_panel.visible = false

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/test_level.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_instructions_pressed() -> void:
	title.visible = false
	center_container.visible = false
	instructions_panel.visible = true

func _on_play_anyway_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/test_level.tscn")
