# Collectible.gd
extends Area3D

signal collected(id: String, message: String)

@export var id: String = ""
@export var message: String = ""

func _ready():
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	# Your player is CharacterBody3D, so this is fine:
	if body is CharacterBody3D:
		emit_signal("collected", id, message)
		queue_free()
