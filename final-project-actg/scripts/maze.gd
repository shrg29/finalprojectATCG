extends Node3D

#default maze look 
@export var maze_width := 25
@export var maze_height := 25
#corridor size 
@export var cell_size := 2.0 
#root scenes
@export var wall_scene: PackedScene
@export var exit_door_scene: PackedScene

#data for grid
var grid := [] #array of cells 
var entrance_cell: Dictionary
var exit_cell: Dictionary

#offset needed to center maze on the floor 
var offset_x := 0.0
var offset_z := 0.0


func _ready():
	if wall_scene == null:
		print("Error: wall_scene not assigned!")
		return
	
	#computing offsets to center maze on floor
	offset_x = -maze_width * cell_size / 2
	offset_z = -maze_height * cell_size / 2
	
	init_grid()
	generate_maze()
	
	#entrance and exit
	entrance_cell = grid[0][0]
	exit_cell = pick_random_exit_cell()
	carve_exit()

	build_maze()
	spawn_exit_door()

	print("Entrance:", entrance_cell)
	print("Exit:", exit_cell)


func pick_random_exit_cell() -> Dictionary:
	var side := randi() % 4

	if side == 0: # top row
		return grid[0][randi() % maze_width]
	elif side == 1: # bottom row
		return grid[maze_height - 1][randi() % maze_width]
	elif side == 2: # left column
		return grid[randi() % maze_height][0]
	else: # right column
		return grid[randi() % maze_height][maze_width - 1]

func carve_exit():
	var x = exit_cell["x"]
	var y = exit_cell["y"]

	if y == 0:
		exit_cell["walls"]["top"] = false
	elif y == maze_height - 1:
		exit_cell["walls"]["bottom"] = false
	elif x == 0:
		exit_cell["walls"]["left"] = false
	elif x == maze_width - 1:
		exit_cell["walls"]["right"] = false

func spawn_exit_door():
	if exit_door_scene == null:
		print("Exit door scene not assigned!")
		return

	var x = exit_cell["x"]
	var y = exit_cell["y"]

	var pos_x = x * cell_size + offset_x
	var pos_z = y * cell_size + offset_z
	var door_pos := Vector3(pos_x, 1.25, pos_z)

	if y == 0:
		door_pos.z -= cell_size / 2
	elif y == maze_height - 1:
		door_pos.z += cell_size / 2
	elif x == 0:
		door_pos.x -= cell_size / 2
	elif x == maze_width - 1:
		door_pos.x += cell_size / 2

	var door = exit_door_scene.instantiate()
	door.position = door_pos
	add_child(door)


#initializing the grid
func init_grid():
	grid.clear()
	for y in maze_height:
		var row := []
		for x in maze_width:
			var cell := {
				"x": x,
				"y": y,
				"visited": false,
				"walls": { "top": true, "bottom": true, "left": true, "right": true }
			}
			row.append(cell)
		grid.append(row)

#maze generation with iterative DFS
func generate_maze():
	var stack := []
	var start_cell: Dictionary = grid[0][0]
	start_cell["visited"] = true
	stack.append(start_cell)

	while stack.size() > 0:
		var current = stack[stack.size() - 1]
		var neighbors = get_unvisited_neighbors(current)
		if neighbors.size() > 0:
			neighbors.shuffle()
			var next_cell = neighbors[0]
			remove_wall_between(current, next_cell)
			next_cell["visited"] = true
			stack.append(next_cell)
		else:
			stack.pop_back()

#getting unvisited neighbors safely
func get_unvisited_neighbors(cell) -> Array:
	var result := []
	var x = cell["x"]
	var y = cell["y"]

	if y > 0 and not grid[y-1][x]["visited"]:
		result.append(grid[y-1][x])  #top
	if y < maze_height-1 and not grid[y+1][x]["visited"]:
		result.append(grid[y+1][x])  #bottom
	if x > 0 and not grid[y][x-1]["visited"]:
		result.append(grid[y][x-1])  #left
	if x < maze_width-1 and not grid[y][x+1]["visited"]:
		result.append(grid[y][x+1])  #right

	return result

#removing walls between adjacent cells
func remove_wall_between(cell_a, cell_b):
	var dx = cell_b["x"] - cell_a["x"]
	var dy = cell_b["y"] - cell_a["y"]

	if dx == 1:
		cell_a["walls"]["right"] = false
		cell_b["walls"]["left"] = false
	elif dx == -1:
		cell_a["walls"]["left"] = false
		cell_b["walls"]["right"] = false
	elif dy == 1:
		cell_a["walls"]["bottom"] = false
		cell_b["walls"]["top"] = false
	elif dy == -1:
		cell_a["walls"]["top"] = false
		cell_b["walls"]["bottom"] = false

#actually building maze in 3D
func build_maze():
	#clear old walls
	for child in get_children():
		child.queue_free()

	for y in maze_height:
		for x in maze_width:
			var cell = grid[y][x]
			var pos_x = x * cell_size + offset_x
			var pos_z = y * cell_size + offset_z

			#top wall
			if cell["walls"]["top"]:
				spawn_wall(pos_x, 0, pos_z - cell_size/2, Vector3(cell_size, 2.0, 0.2))
			#bottom wall
			if cell["walls"]["bottom"]:
				spawn_wall(pos_x, 0, pos_z + cell_size/2, Vector3(cell_size, 2.0, 0.2))
			#left wall
			if cell["walls"]["left"]:
				spawn_wall(pos_x - cell_size/2, 0, pos_z, Vector3(0.2, 2.0, cell_size))
			#right wall
			if cell["walls"]["right"]:
				spawn_wall(pos_x + cell_size/2, 0, pos_z, Vector3(0.2, 2.0, cell_size))

#spawn individual wall
func spawn_wall(x: float, y: float, z: float, size: Vector3):
	if wall_scene == null:
		return
	var wall = wall_scene.instantiate()
	wall.transform.origin = Vector3(x, y + size.y/2, z)
	wall.scale = size
	add_child(wall)

#regenerate maze 
func regenerate_maze():
	init_grid()
	generate_maze()
	build_maze()

#cell centers perfect for anchors 
func get_random_cell_world_position(y_height: float = 1.0) -> Vector3:
	var x := randi() % maze_width
	var y := randi() % maze_height

	var pos_x := x * cell_size + offset_x
	var pos_z := y * cell_size + offset_z

	# local -> world (important if Maze node is moved)
	return to_global(Vector3(pos_x, y_height, pos_z))
