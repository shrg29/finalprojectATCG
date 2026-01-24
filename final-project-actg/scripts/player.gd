extends CharacterBody3D

signal sprinting_changed(is_sprinting: bool)
signal punish_requested()

var _is_sprinting_now := false

#basic player vars
@export var speed = 1.5
@export var sprint_speed := 5.0
@export var mouse_sensitivity = 0.2
@export var gravity : float = -9.8
@export var jump_velocity := 4.5

#stamina system vars
#max stamina you can have
@export var max_stamina := 10.0     
#drains per second while sprinting    
@export var stamina_drain_rate := 4.2   
#recharges per second when not sprinting
@export var stamina_recovery_rate := 3.0
#35% out of max stamina - unlocks sprint 
@export var stamina_lock_threshold := 0.40 

var stamina := max_stamina
var can_sprint := true

#danger level system
#increases while walking
@export var danger_increase_rate := 0.32
#decreases while walking/standing still
@export var danger_decrease_rate := 0.14
#upper limit danger
@export var max_danger := 10.0
#sprint multiplies danger level 
@export var sprint_danger_multiplier := 4.0

#awareness system 
@export var view_dot_threshold := 0.85
# 0.85 ≈ ~31° cone. Lower = wider cone.
@export var look_time_to_trigger := 0.60
# seconds before "punish" should happen
@export var awareness_debug := true
var is_looking_at_enemy := false
var look_timer := 0.0

@onready var stamina_label := $CanvasLayer/StaminaLabel
@onready var danger_label := $CanvasLayer/DangerLabel
@onready var camera_pivot = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var awareness_label := $CanvasLayer/AwarenessLabel
@onready var director_label := $CanvasLayer/DirectorLabel

#door vars
#how far ahead to check for a door
@export var push_distance := 1.5
#how hard the player pushes      
@export var push_force := 5.0        

var danger_level := 0.0
var rotation_y = 0.0
var rotation_x = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	handle_mouse_look(event)

#player movement
func _physics_process(delta):
	var move_dir := get_movement_direction()
	var is_trying_to_sprint := Input.is_action_pressed("sprint") and move_dir != Vector3.ZERO
	var is_sprinting := is_trying_to_sprint and can_sprint
	var is_moving := move_dir != Vector3.ZERO
	
	if is_sprinting != _is_sprinting_now:
		_is_sprinting_now = is_sprinting
		emit_signal("sprinting_changed", _is_sprinting_now)

	
	AudioManager.set_movement_active(is_moving)
	AudioManager.set_sprinting(is_sprinting)

	apply_movement(move_dir, is_sprinting)
	apply_gravity(delta)
	handle_jump()
	update_stamina(delta, is_sprinting)
	update_danger(delta, move_dir != Vector3.ZERO, is_sprinting)
	update_debug_ui()

	move_and_slide()
	push_door_ahead()
	update_awareness(delta)
	update_awareness_ui()


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
		
#jumping enabled
func handle_jump():
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


#pushing the door 
func push_door_ahead():
	var from: Vector3 = camera_pivot.global_position
	var forward: Vector3 = -camera_pivot.global_transform.basis.z
	var to: Vector3 = from + forward * push_distance

	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	params.collide_with_areas = false
	params.collide_with_bodies = true

	var result := get_world_3d().direct_space_state.intersect_ray(params)
	if result.is_empty():
		return

	var collider = result["collider"]
	if collider is RigidBody3D:
		#push in the direction we are looking
		collider.apply_central_impulse(forward * push_force)

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

#awareness system 
func update_awareness_ui():
	if awareness_label == null:
		return

	var status := "NO ENEMY"
	var color := Color(1, 1, 1)

	var enemy := get_enemy()
	if enemy != null:
		if is_looking_at_enemy:
			status = "LOOKING (%.2fs)" % look_timer
			color = Color(1, 0.3, 0.3) # red-ish
		else:
			status = "NOT LOOKING"
			color = Color(0.8, 0.8, 0.8)

	awareness_label.text = "Awareness: " + status
	awareness_label.modulate = color

#UI debug for danger and stamina systems
func update_debug_ui():
	danger_label.text = "Danger: %.2f" % danger_level
	danger_label.modulate = Color(
		1.0,
		1.0 - danger_level / max_danger,
		1.0 - danger_level / max_danger
	)
	stamina_label.text = "Stamina: %d/%d" % [round(stamina), max_stamina]

#console output debug for awereness	
func update_awareness(delta):
	var enemy := get_enemy()
	if enemy == null:
		is_looking_at_enemy = false
		look_timer = 0.0
		return

	is_looking_at_enemy = is_enemy_visible(enemy)

	if is_looking_at_enemy:
		look_timer += delta
		if awareness_debug:
			print("Looking at enemy: ", "%.2f" % look_timer)
		if look_timer >= look_time_to_trigger:
			if awareness_debug:
				print(">>> PUNISH SHOULD TRIGGER NOW <<<")
			emit_signal("punish_requested")
			look_timer = 0.0 # prevents spamming
	else:
		look_timer = 0.0

#debug for enemy 	
func set_director_debug_text(t: String, c: Color = Color(1,1,1)) -> void:
	if director_label == null:
		return
	director_label.text = t
	director_label.modulate = c

#finding current manifested enemy, if one exists
#deliberately allowing only one enemy at time 
func get_enemy() -> Node3D:
	var node = get_tree().get_first_node_in_group("enemy")
	return node as Node3D

#is the enemy currently visible in physical sense (in front of the camera)
func is_enemy_visible(enemy: Node3D) -> bool:
	
	#checking if enemy is clearly in front
	#not just barely on the edge of vision 
	var forward: Vector3 = -camera.global_transform.basis.z
	forward = forward.normalized()
	var to_enemy: Vector3 = (enemy.global_position - camera.global_position).normalized()
	var dot := forward.dot(to_enemy)

	if dot < view_dot_threshold:
		return false

	#checking line of sight raycast
	#if blocked by wall - no enemy
	#if enemy - enemy visible 
	var from: Vector3 = camera.global_position
	var to: Vector3 = enemy.global_position

	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	params.collide_with_areas = false
	params.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return false

	return hit["collider"] == enemy

#checking for invisible stuff
#anchors, enemy presence
#deciding when enemy is allowed to manifest 
func can_see_point(world_point: Vector3, dot_threshold: float = -1.0) -> bool:
	var threshold := view_dot_threshold if dot_threshold < 0.0 else dot_threshold

	#player must face the anchor 
	var forward: Vector3 = -camera.global_transform.basis.z
	forward = forward.normalized()

	var to_point: Vector3 = (world_point - camera.global_position).normalized()
	var dot := forward.dot(to_point)
	if dot < threshold:
		return false

	#line of sight to a point
	var from: Vector3 = camera.global_position
	var to: Vector3 = world_point

	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	params.collide_with_areas = false
	params.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(params)

	#if nothing blocks, we can see the point
	if hit.is_empty():
		return true

	#if something is hit, it's blocking the point
	#we don't have a collider at the point, so any hit means blocked
	return false
	
func set_near_enemy_fx(on: bool) -> void:
	$ScreenFX/FlickerRect.set_flicker_active(on)
