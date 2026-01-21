extends Node3D

#horror direction that controls an invisible enemy presence using anchors 
#manifesting a real enemy only when rules are met 

enum State { COOLDOWN, ANCHORED, MANIFESTED, PUNISH }

@export var maze_path: NodePath
@export var player_path: NodePath

@export var manifested_enemy_scene: PackedScene

#debug exports 
@export var debug_enabled := true
@export var debug_show_anchor_markers := true
@export var debug_marker_size := 0.15
@export var debug_print_every := 0.5 #seconds (console spam limiter)

#anchor generation
@export var anchors_count := 60
@export var anchor_y := 1.0

#timing/pacing
@export var base_anchor_interval := 8.0         #seconds between anchor picks when calm
@export var sprint_interval_multiplier := 0.45  #sprinting => shorter interval (more frequent picks)
@export var danger_interval_factor := 0.35      #danger pushes interval down (0..1 factor weight)

@export var base_cooldown := 6.0                #after clearing anchor/demanifest
@export var sprint_cooldown_multiplier := 0.6   #sprinting slows "recovery" (smaller = longer effective cooldown)
@export var danger_cooldown_factor := 0.5

#distances (in meters)
@export var far_dist := 18.0
@export var mid_dist := 12.0
@export var near_dist := 7.0

#anchor must be this close AND visible to manifest
@export var manifest_distance := 10.0
@export var manifest_view_dot := 0.85

#if player looks away after manifest, we clear anchor after a short grace
@export var lose_sight_clear_time := 0.35
var _lose_sight_timer := 0.0

#punish spawn
@export var punish_distance_from_camera := 1.2
@export var punish_duration := 1.2

#audio
@export var cue_far: AudioStream
@export var cue_breath: AudioStream
@export var cue_tense: AudioStream

@export var audio_bus := "Music"
@export var audio_fade_speed := 6.0
@export var active_db := -8.0
@export var off_db := -40.0

@export var breath_pitch_mid := 1.0
@export var breath_pitch_near := 1.35
@export var pitch_fade_speed := 6.0

@export var breath_db_mid := -8.0
@export var breath_db_near := -2.0

var _repick_timer := 0.0

var _debug_markers_root: Node3D
var _debug_timer := 0.0


var _maze: Node3D
var _player: Node3D

var _anchors: Array[Vector3] = []
var _anchor_index := -1
var _anchor_pos := Vector3.ZERO

var _state := State.COOLDOWN
var _timer := 0.0
var _is_sprinting := false

var _manifested: Node3D = null

#audio players
var _p_far: AudioStreamPlayer
var _p_breath: AudioStreamPlayer
var _p_tense: AudioStreamPlayer

var _t_far := off_db
var _t_breath := off_db
var _t_tense := off_db
var _t_breath_pitch := 1.0


func _ready():
	_maze = get_node_or_null(maze_path) as Node3D
	_player = get_node_or_null(player_path) as Node3D

	if _maze == null or _player == null:
		push_error("EnemyDirector: maze_path or player_path not set.")
		return

	#connecting to maze and player 
	#sprinting affects pacing
	#punish triggers jumpscare
	_player.connect("sprinting_changed", Callable(self, "_on_player_sprinting_changed"))
	_player.connect("punish_requested", Callable(self, "_on_player_punish_requested"))

	#creating 3 audioplayers for audio cues 
	_build_audio()
	#generating list of random positions in maze 
	_generate_anchors()
	if debug_enabled and debug_show_anchor_markers:
		_create_debug_markers() #debug spheres for anchors 

	#cooldown is the beginning state 
	_enter_cooldown("start")

func _process(delta: float) -> void:
	if _maze == null or _player == null:
		return
	#every frame it updates audio fade and pitch 
	_update_audio(delta)
	if debug_enabled and debug_show_anchor_markers:
		_highlight_active_anchor() #currently chosen anchor is a bit bigger 

	match _state:
		#enemy waits until cooldown ends so it can anchor itself
		#basically headstart for the player 
		State.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_pick_new_anchor()
		#computing the distance between player and anchor 
		#setting audio targets + breathing 
		State.ANCHORED:
			_update_anchor_pressure(delta)
			_repick_timer -= delta
			if _repick_timer <= 0.0:
		#picks a new anchor
		#more often when sprinting/high danger level 
				_pick_new_anchor()
				return
			if _can_manifest_now():
				_manifest_at_anchor()
		#if anchor is close enough and visible, spawn real enemy 
		State.MANIFESTED:
			_update_manifested(delta)
		#if player looks at the enemy for too long - punish
		State.PUNISH:
			_timer -= delta
			if _timer <= 0.0:
				_end_punish()
				
	#updates every half a second 
	_debug_update(delta)

#anchor generation/picking
func _generate_anchors() -> void:
	_anchors.clear()
	for i in anchors_count:
		var p := Vector3(_maze.call("get_random_cell_world_position", anchor_y))
		_anchors.append(p)

#having exactly one active anchor 
func _pick_new_anchor() -> void:
	if _anchors.is_empty():
		return

	#pick a different index than last time if possible
	var new_idx := randi() % _anchors.size()
	if _anchors.size() > 1 and new_idx == _anchor_index:
		new_idx = (new_idx + 1) % _anchors.size()

	_anchor_index = new_idx
	_anchor_pos = _anchors[_anchor_index]
	_state = State.ANCHORED
	_lose_sight_timer = 0.0
	_repick_timer = _get_next_anchor_interval()
	
#debug spheres for anchors 
func _create_debug_markers() -> void:
	_debug_markers_root = Node3D.new()
	_debug_markers_root.name = "AnchorDebugMarkers"
	add_child(_debug_markers_root)

	#create tiny spheres for each anchor
	var sphere := SphereMesh.new()
	sphere.radius = debug_marker_size
	sphere.height = debug_marker_size * 2.0

	for i in _anchors.size():
		var m := MeshInstance3D.new()
		m.mesh = sphere
		m.global_position = _anchors[i]
		_debug_markers_root.add_child(m)

func _highlight_active_anchor() -> void:
	#scale the active one up 
	if _debug_markers_root == null:
		return
	for i in _debug_markers_root.get_child_count():
		var child := _debug_markers_root.get_child(i) as Node3D
		if child == null:
			continue
		if i == _anchor_index:
			child.scale = Vector3.ONE * 2.5
		else:
			child.scale = Vector3.ONE

#audio choosing based off of distance 
func _update_anchor_pressure(delta: float) -> void:
	var player_pos: Vector3 = _player.global_position
	var d := player_pos.distance_to(_anchor_pos)

	#choose audio tier by distance
	if d <= near_dist:
		_t_breath_pitch = breath_pitch_near
		_set_audio_targets(off_db, breath_db_near, active_db) #breath louder + tense ON
	elif d <= mid_dist:
		_t_breath_pitch = breath_pitch_mid
		_set_audio_targets(active_db, breath_db_mid, off_db)  #far + breath
	elif d <= far_dist:
		_t_breath_pitch = breath_pitch_mid
		_set_audio_targets(active_db, off_db, off_db)         #far only
	else:
		_t_breath_pitch = breath_pitch_mid
		_set_audio_targets(off_db, off_db, off_db)            #silent

func _set_audio_targets(far_db: float, breath_db: float, tense_db: float) -> void:
	_t_far = far_db
	_t_breath = breath_db
	_t_tense = tense_db

func _update_audio(delta: float) -> void:
	if _p_far:
		_p_far.volume_db = lerp(_p_far.volume_db, _t_far, delta * audio_fade_speed)

	if _p_breath:
		_p_breath.volume_db = lerp(_p_breath.volume_db, _t_breath, delta * audio_fade_speed)
		_p_breath.pitch_scale = lerp(_p_breath.pitch_scale, _t_breath_pitch, delta * pitch_fade_speed)

	if _p_tense:
		_p_tense.volume_db = lerp(_p_tense.volume_db, _t_tense, delta * audio_fade_speed)

#udio system (3 layers)
func _build_audio() -> void:
	_p_far = _make_player(cue_far)
	_p_breath = _make_player(cue_breath)
	_p_tense = _make_player(cue_tense)

#manifesting enemy under conditions
func _can_manifest_now() -> bool:
	var player_pos: Vector3 = _player.global_position
	var d := player_pos.distance_to(_anchor_pos)
	if d > manifest_distance:
		return false

	#based on distance to anchor
	#if player can see the anchor point
	return bool(_player.call("can_see_point", _anchor_pos, manifest_view_dot))

#spawning real enemy node to anchor and adds it to the group "enemy"
func _manifest_at_anchor() -> void:
	if manifested_enemy_scene == null:
		push_warning("EnemyDirector: manifested_enemy_scene missing.")
		return

	_manifested = manifested_enemy_scene.instantiate() as Node3D
	if _manifested == null:
		push_warning("EnemyDirector: instantiated enemy is not Node3D.")
		return

	get_tree().current_scene.add_child(_manifested)

	_manifested.global_position = _anchor_pos
	_manifested.look_at(_player.global_position, Vector3.UP)
	_manifested.add_to_group("enemy")

	_state = State.MANIFESTED
	_lose_sight_timer = 0.0

#checking if player sees the enemy 
func _update_manifested(delta: float) -> void:
	#while manifested, keep audio tense
	_set_audio_targets(off_db, active_db, active_db)

	if _manifested == null:
		_state = State.ANCHORED
		return
	#if player looks aways, enemy disappears 
	#cooldown starts 
	var sees: bool = bool(_player.call("is_enemy_visible", _manifested))
	if sees:
		_lose_sight_timer = 0.0
	else:
		_lose_sight_timer += delta
		if _lose_sight_timer >= lose_sight_clear_time:
			_demanifest_and_clear("player looked away")

#punishment system 
#emitted when look timer exceeds treshold 
func _on_player_punish_requested() -> void:
	# Punish only if there's something to punish (manifested)
	if _state != State.MANIFESTED:
		return

	_start_punish()

#delets the manifested enemy and spawns it in front of the camera 
func _start_punish() -> void:
	_state = State.PUNISH
	_timer = punish_duration

	#remove anchor monster
	if is_instance_valid(_manifested):
		_manifested.queue_free()
	_manifested = null

	#spawn jumpscare in front of camera
	var cam := _player.get_node("CameraPivot/Camera3D") as Camera3D
	if cam == null or manifested_enemy_scene == null:
		return

	var jump := manifested_enemy_scene.instantiate() as Node3D
	if jump == null:
		return

	get_tree().current_scene.add_child(jump)

	var forward := -cam.global_transform.basis.z
	jump.global_position = cam.global_position + forward * punish_distance_from_camera
	jump.global_rotation = cam.global_rotation
	jump.add_to_group("enemy")

	_manifested = jump

	#push audio hard tense
	_set_audio_targets(off_db, active_db, active_db)

#removes enemy and goes cooldown 
func _end_punish() -> void:
	if is_instance_valid(_manifested):
		_manifested.queue_free()
	_manifested = null

	_anchor_index = -1
	_set_audio_targets(off_db, off_db, off_db)
	_enter_cooldown("punish ended")

func _demanifest_and_clear(reason: String = "") -> void:
	if is_instance_valid(_manifested):
		_manifested.queue_free()
	_manifested = null

	_anchor_index = -1
	_set_audio_targets(off_db, off_db, off_db)
	_enter_cooldown(reason)

#coldown + pacing influenced by sprint/danger
func _enter_cooldown(reason: String = "") -> void:
	_state = State.COOLDOWN

	var danger := _get_player_danger01()
	var cd := base_cooldown

	#running slows recovery => longer cooldown
	if _is_sprinting:
		cd = cd / max(0.05, sprint_cooldown_multiplier)

	#more danger => longer cooldown
	cd *= lerp(1.0, 1.0 + danger_cooldown_factor, danger)

	_timer = cd

#depends on player style of play 
func _get_next_anchor_interval() -> float:
	var danger := _get_player_danger01()

	var interval := base_anchor_interval
	if _is_sprinting:
		interval *= sprint_interval_multiplier

	#danger reduces interval => more frequent anchor selection
	interval *= lerp(1.0, 1.0 - danger_interval_factor, danger)

	return max(0.8, interval)

func _get_player_danger01() -> float:
	# Variant-safe: if property missing, get() returns null -> float(null)=0.0
	var dl := float(_player.get("danger_level"))
	var md := float(_player.get("max_danger"))
	if md <= 0.0:
		return 0.0
	return clamp(dl / md, 0.0, 1.0)

func _on_player_sprinting_changed(s: bool) -> void:
	_is_sprinting = s

func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = audio_bus
	p.stream = stream
	p.volume_db = off_db
	add_child(p)
	if stream != null:
		p.play()
	return p

#UI debug for enemy closeness 
func _debug_update(delta: float) -> void:
	if not debug_enabled:
		return

	_debug_timer += delta
	if _debug_timer < debug_print_every:
		return
	_debug_timer = 0.0

	#distance to current anchor (this is what drives audio tiers)
	var d := INF
	if _anchor_index >= 0:
		d = _player.global_position.distance_to(_anchor_pos)

	#simple tier labels
	var enemy_text := "ENEMY: NONE"
	var audio_text := "AUDIO: SILENT"

	if _state == State.COOLDOWN:
		enemy_text = "ENEMY: NONE"
		audio_text = "AUDIO: SILENT"
	elif _state == State.PUNISH:
		enemy_text = "ENEMY: PUNISH"
		audio_text = "AUDIO: INTENSE"
	else:
		#ANCHORED or MANIFESTED: use distance tiers
		if d <= near_dist:
			enemy_text = "ENEMY: VERY CLOSE"
			audio_text = "AUDIO: INTENSE"
		elif d <= mid_dist:
			enemy_text = "ENEMY: CLOSER"
			audio_text = "AUDIO: BREATHING"
		elif d <= far_dist:
			enemy_text = "ENEMY: FAR AWAY"
			audio_text = "AUDIO: FIRST CUE"
		else:
			enemy_text = "ENEMY: LOST"
			audio_text = "AUDIO: SILENT"

	#show state on a small third line (remove if you want)
	var state_line := ""
	if _state == State.ANCHORED:
		state_line = "STATE: ANCHORED"
	elif _state == State.MANIFESTED:
		state_line = "STATE: MANIFESTED"
	elif _state == State.COOLDOWN:
		state_line = "STATE: COOLDOWN"
	elif _state == State.PUNISH:
		state_line = "STATE: PUNISH"

	var info := enemy_text + "\n" + audio_text + "\n" + state_line

	var col := Color(0.8, 0.9, 1.0)
	if _state == State.MANIFESTED:
		col = Color(1, 0.6, 0.3)
	elif _state == State.PUNISH:
		col = Color(1, 0.2, 0.2)
	elif _state == State.COOLDOWN:
		col = Color(0.7, 0.7, 0.7)

	print(info)

	if _player.has_method("set_director_debug_text"):
		_player.call("set_director_debug_text", info, col)
		
		
