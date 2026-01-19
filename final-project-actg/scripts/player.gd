extends CharacterBody3D

@export var speed = 5.0
@export var mouse_sensitivity = 0.2
@export var gravity : float = -9.8

var rotation_y = 0.0
var rotation_x = 0.0

@onready var camera_pivot = $CameraPivot

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		# Horizontal rotation on player
		rotation_y -= deg_to_rad(event.relative.x * mouse_sensitivity)
		rotation.y = rotation_y
		
		# Vertical rotation on camera pivot
		rotation_x -= deg_to_rad(event.relative.y * mouse_sensitivity)
		rotation_x = clamp(rotation_x, deg_to_rad(-89), deg_to_rad(89))
		camera_pivot.rotation.x = rotation_x

func _physics_process(delta):
	var direction = Vector3.ZERO

	# Input mapping (make sure these match your Input Map!)
	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		direction += transform.basis.z
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		direction += transform.basis.x

	# Normalize to avoid faster diagonal movement
	if direction.length() > 0:
		direction = direction.normalized() * speed

	# Assign to CharacterBody3D velocity (keep Y for gravity)
	velocity.x = direction.x
	velocity.z = direction.z

	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0

	# Move player
	move_and_slide()
