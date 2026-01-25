# CueDirector.gd
extends Node3D

@export var maze_path: NodePath
@export var player_path: NodePath
@export var cue_ui_path: NodePath

@export var collectible_scene: PackedScene

# messages for your 3 cues
@export var cue1_text := "..."
@export var cue2_text := "..."
@export var cue3_text := "..."

@export var cue1_min_distance_from_player := 0.4

# placement tuning
@export var cue_height := 0.8
@export var cue1_radius_near_player := 5.0   # spawn within this range of player
@export var cue2_radius_near_exit := 6.0     # spawn within this range of exit
@export var pick_attempts := 40

@export var cue3_min_distance_from_cue1 := 10.0
@export var cue3_min_distance_from_cue2 := 10.0

var _cue1_pos := Vector3.ZERO
var _cue2_pos := Vector3.ZERO


var _maze: Node3D
var _player: Node3D
var _cue_ui: CanvasLayer

var _cue1_read := false

func _ready() -> void:
	_maze = get_node_or_null(maze_path) as Node3D
	_player = get_node_or_null(player_path) as Node3D
	_cue_ui = get_node_or_null(cue_ui_path) as CanvasLayer

	if _maze == null or _player == null or _cue_ui == null:
		push_error("CueDirector: paths not set (maze/player/cue_ui).")
		return
	if collectible_scene == null:
		push_error("CueDirector: collectible_scene not assigned.")
		return

	# Wait one frame so Maze _ready() finishes generating exit/entrance
	await get_tree().process_frame

	_spawn_cue1_near_player()

func _spawn_collectible(id: String, message: String, pos: Vector3) -> void:
	var c := collectible_scene.instantiate() as Area3D
	if c == null:
		push_warning("CueDirector: collectible scene root must be Area3D.")
		return

	# set exported vars on Collectible.gd
	c.set("id", id)
	c.set("message", message)

	get_tree().current_scene.add_child(c)
	c.global_position = pos

	# connect to its signal
	c.connect("collected", Callable(self, "_on_collectible_collected"))

func _on_collectible_collected(id: String, message: String) -> void:
	# show your UI and pause
	_cue_ui.call("show_message", message)

	if id == "cue1" and not _cue1_read:
		_cue1_read = true
		_spawn_cue2_and_cue3()

func _spawn_cue1_near_player() -> void:
	var player_pos: Vector3 = _player.global_position

	var best := Vector3.ZERO
	var best_d := INF

	for i in range(pick_attempts):
		var p: Vector3 = _maze.call("get_random_cell_world_position", cue_height)
		var d: float = p.distance_to(player_pos)

		# must be far enough AND close enough
		if d >= cue1_min_distance_from_player and d <= cue1_radius_near_player:
			_cue1_pos = p
			_spawn_collectible("cue1", cue1_text, _cue1_pos)
			return

		# fallback: closest but still not too close
		if d >= cue1_min_distance_from_player and d < best_d:
			best_d = d
			best = p

	# fallback spawn (guaranteed visible)
	_cue1_pos = best
	_spawn_collectible("cue1", cue1_text, _cue1_pos)



func _spawn_cue2_and_cue3() -> void:
	# Cue2: near exit
	var exit_pos: Vector3 = _maze.call("get_exit_world_position", cue_height)
	_cue2_pos = _pick_random_cell_near_point(exit_pos, cue2_radius_near_exit)

	# Cue3: random but far from cue1 and cue2
	var cue3_pos := _pick_random_cell_avoiding(
		_cue1_pos, cue3_min_distance_from_cue1,
		_cue2_pos, cue3_min_distance_from_cue2
	)

	_spawn_collectible("cue2", cue2_text, _cue2_pos)
	_spawn_collectible("cue3", cue3_text, cue3_pos)


func _pick_random_cell_near_point(center: Vector3, radius: float) -> Vector3:
	# Try to pick a random maze cell within radius of 'center'
	var best := Vector3.ZERO
	var best_d := INF

	for i in range(pick_attempts):
		var p: Vector3 = _maze.call("get_random_cell_world_position", cue_height)
		var d := p.distance_to(center)
		if d <= radius:
			return p
		# keep closest as fallback (in case radius is too strict)
		if d < best_d:
			best_d = d
			best = p

	# fallback: closest attempt
	return best

func _pick_random_cell_avoiding(a_pos: Vector3, a_min: float, b_pos: Vector3, b_min: float) -> Vector3:
	var best := Vector3.ZERO
	var best_score := -INF

	for i in range(pick_attempts * 2):
		var p: Vector3 = _maze.call("get_random_cell_world_position", cue_height)

		var da := p.distance_to(a_pos)
		var db := p.distance_to(b_pos)

		# accept if far enough from BOTH
		if da >= a_min and db >= b_min:
			return p

		# fallback scoring: maximize the minimum distance to the two cues
# fallback scoring: maximize the minimum distance to the two cues
		var score: float = min(
			da / max(a_min, 0.001),
			db / max(b_min, 0.001)
		)

		if score > best_score:
			best_score = score
			best = p

	# fallback: “best effort” if maze is too small / constraints too strict
	return best
