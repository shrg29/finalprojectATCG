extends Node3D

@export var player_path: NodePath
var player: Node3D

func _ready():
	player = get_node(player_path)

func _process(delta):
	if player:
		# Keep rain horizontally centered on the player
		global_transform.origin.x = player.global_transform.origin.x
		global_transform.origin.z = player.global_transform.origin.z
