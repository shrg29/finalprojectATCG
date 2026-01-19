extends Node3D

# ---------- Maze Settings ----------
@export var maze_width := 25
@export var maze_height := 25
@export var cell_size := 2.0   # size of one corridor

@export var wall_scene: PackedScene  # drag your wall scene (StaticBody3D root)

# ---------- Grid Data ----------
var grid := []  # 2D array of cells
var entrance_cell: Dictionary
var exit_cell: Dictionary

# --- Maze Offset to center on floor ---
var offset_x := 0.0
var offset_z := 0.0


func _ready():
	if wall_scene == null:
		print("Error: wall_scene not assigned!")
		return
	
	# --- Compute offsets to center maze on floor ---
	offset_x = -maze_width * cell_size / 2
	offset_z = -maze_height * cell_size / 2
	
	init_grid()
	generate_maze()
	build_maze()
	
	# Entrance / Exit
	entrance_cell = grid[0][0]
	exit_cell = grid[maze_height-1][maze_width-1]
	print("Entrance:", entrance_cell)
	print("Exit:", exit_cell)



# ---------------------
# Initialize the grid
# ---------------------
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


# ---------------------
# Maze Generation (Iterative DFS)
# ---------------------
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


# ---------------------
# Get unvisited neighbors safely
# ---------------------
func get_unvisited_neighbors(cell) -> Array:
	var result := []
	var x = cell["x"]
	var y = cell["y"]

	if y > 0 and not grid[y-1][x]["visited"]:
		result.append(grid[y-1][x])  # top
	if y < maze_height-1 and not grid[y+1][x]["visited"]:
		result.append(grid[y+1][x])  # bottom
	if x > 0 and not grid[y][x-1]["visited"]:
		result.append(grid[y][x-1])  # left
	if x < maze_width-1 and not grid[y][x+1]["visited"]:
		result.append(grid[y][x+1])  # right

	return result


# ---------------------
# Remove walls between adjacent cells
# ---------------------
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


# ---------------------
# Build maze in 3D
# ---------------------
func build_maze():
	# Clear old walls
	for child in get_children():
		child.queue_free()

	for y in maze_height:
		for x in maze_width:
			var cell = grid[y][x]
			var pos_x = x * cell_size + offset_x
			var pos_z = y * cell_size + offset_z

			# Top wall
			if cell["walls"]["top"]:
				spawn_wall(pos_x, 0, pos_z - cell_size/2, Vector3(cell_size, 2.0, 0.2))
			# Bottom wall
			if cell["walls"]["bottom"]:
				spawn_wall(pos_x, 0, pos_z + cell_size/2, Vector3(cell_size, 2.0, 0.2))
			# Left wall
			if cell["walls"]["left"]:
				spawn_wall(pos_x - cell_size/2, 0, pos_z, Vector3(0.2, 2.0, cell_size))
			# Right wall
			if cell["walls"]["right"]:
				spawn_wall(pos_x + cell_size/2, 0, pos_z, Vector3(0.2, 2.0, cell_size))


# ---------------------
# Spawn individual wall
# ---------------------
func spawn_wall(x: float, y: float, z: float, size: Vector3):
	if wall_scene == null:
		return
	var wall = wall_scene.instantiate()
	wall.transform.origin = Vector3(x, y + size.y/2, z)
	wall.scale = size
	add_child(wall)


# ---------------------
# Regenerate maze
# ---------------------
func regenerate_maze():
	init_grid()
	generate_maze()
	build_maze()
