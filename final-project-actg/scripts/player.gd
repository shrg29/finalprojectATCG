extends CharacterBody3D

#basic player vars
@export var speed = 2.0
@export var sprint_speed := 7.0
@export var mouse_sensitivity = 0.2
@export var gravity : float = -9.8

#stamina system vars
#max stamina you can have
@export var max_stamina := 20.0     
#drains per second while sprinting    
@export var stamina_drain_rate := 5.0   
#recharges per second when not sprinting
@export var stamina_recovery_rate := 4.0
#35% out of max stamina - unlocks sprint 
@export var stamina_lock_threshold := 0.35 

var stamina := max_stamina
var can_sprint := true

#danger level system
#increases while walking
@export var danger_increase_rate := 0.15
#decreases while walking/standing still
@export var danger_decrease_rate := 0.25
#upper limit danger
@export var max_danger := 10.0
#sprint multiplies danger level 
@export var sprint_danger_multiplier := 5.0

@onready var stamina_label := $CanvasLayer/StaminaLabel
@onready var danger_label := $CanvasLayer/DangerLabel
@onready var camera_pivot = $CameraPivot

var danger_level := 0.0
var rotation_y = 0.0
var rotation_x = 0.0


func _ready():
	pass
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	handle_mouse_look(event)

#player movement
func _physics_process(delta):
	var move_dir := get_movement_direction()
	var is_trying_to_sprint := Input.is_action_pressed("sprint") and move_dir != Vector3.ZERO
	var is_sprinting := is_trying_to_sprint and can_sprint

	apply_movement(move_dir, is_sprinting)
	apply_gravity(delta)
	update_stamina(delta, is_sprinting)
	update_danger(delta, move_dir != Vector3.ZERO, is_sprinting)
	update_debug_ui()

	move_and_slide()

#look around with mouse
func handle_mouse_look(event):
	if event is InputEventMouseMotion:
		rotation_y -= deg_to_rad(event.relative.x * mouse_sensitivity)
		rotation.y = rotation_y

		rotation_x -= deg_to_rad(event.relative.y * mouse_sensitivity)
		rotation_x = clamp(rotation_x, deg_to_rad(-89), deg_to_rad(89))
		camera_pivot.rotation.x = rotation_x

#WASD implementation 
func get_movement_direction() -> Vector3:
		var dir := Vector3.ZERO

		if Input.is_action_pressed("move_forward"):
			dir -= transform.basis.z
		if Input.is_action_pressed("move_backward"):
			dir += transform.basis.z
		if Input.is_action_pressed("move_left"):
			dir -= transform.basis.x
		if Input.is_action_pressed("move_right"):
			dir += transform.basis.x

		return dir.normalized()

#player stuff
func apply_movement(direction: Vector3, sprinting: bool):
	var current_speed : float = sprint_speed if sprinting else speed

	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed
func apply_gravity(delta):
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0

#stamina system
#draining and recharging
func update_stamina(delta, sprinting: bool):
	if sprinting:
		stamina -= stamina_drain_rate * delta
		if stamina <= 0:
			stamina = 0
			can_sprint = false
	else:
		stamina += stamina_recovery_rate * delta
		if stamina > max_stamina:
			stamina = max_stamina
		
		# unlock sprint if above threshold
		if not can_sprint and stamina / max_stamina >= stamina_lock_threshold:
			can_sprint = true

#danger system 
#increases while walking
#multiplies while sprinting
#decreases when standing or walking after sprinting
func update_danger(delta, is_moving: bool, sprinting: bool):
	if is_moving:
		var multiplier := sprint_danger_multiplier if sprinting else 1.0
		danger_level += danger_increase_rate * multiplier * delta
	else:
		danger_level -= danger_decrease_rate * delta

	danger_level = clamp(danger_level, 0.0, max_danger)

#helper UI
#dev only 
func update_debug_ui():
	danger_label.text = "Danger: %.2f" % danger_level
	danger_label.modulate = Color(
		1.0,
		1.0 - danger_level / max_danger,
		1.0 - danger_level / max_danger
	)
	stamina_label.text = "Stamina: %d/%d" % [round(stamina), max_stamina]
