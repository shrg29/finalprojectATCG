extends Node

#movement music
@export var walk_pitch := 1.0
@export var sprint_pitch := 2.0
@export var fade_speed := 8.0
#when player stops moving, fade out then stop
@export var fade_out_db := -30.0

var _target_pitch := 1.0
var _target_db := fade_out_db
var _base_db := -6.0
var _player: AudioStreamPlayer
var _is_active := false

@onready var movement_music: AudioStream = preload("res://assets/audio/walking.mp3")
#udio system (3 layers)
@onready var cue_far: AudioStream = preload("res://assets/audio/first_cue.mp3")
@onready var cue_breath: AudioStream = preload("res://assets/audio/breathing.mp3")

@export var enemy_bus := "Enemy"
@export var enemy_fade_speed := 6.0
@export var enemy_active_db := -8.0
@export var enemy_off_db := -40.0

@export var breath_pitch_mid := 1.0
@export var breath_pitch_near := 1.35
@export var pitch_fade_speed := 6.0

@export var breath_db_mid := -8.0
@export var breath_db_near := -2.0

#far cue "nice beginning" (so it doesn't feel like it starts out of nowhere)
@export var far_attack_time := 1.0        #0.6–1.2 feels good for horror
@export var far_attack_from_db := -60.0   #start basically inaudible
@export var far_retrigger_silence_db := -45.0 #must be below this to count as "silent"

#near range background music is lower (bed stays, but quieter)
@export var near_bed_db := -18.0

#audio players
var _p_far: AudioStreamPlayer
var _p_breath: AudioStreamPlayer

var _t_far := -40.0
var _t_breath := -40.0
var _t_breath_pitch := 1.0

#state for far cue "attack"
var _far_attack_timer := 0.0
var _far_was_audible := false

#distance tiers (mirrors your director tiers)
enum EnemyTier { SILENT = -1, FAR = 0, MID = 1, NEAR = 2 }

func _ready():
	_t_far = enemy_off_db
	_t_breath = enemy_off_db
	#movement music player
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)
	#set default movement music here (no need for Player to pass it in)
	set_music_track(movement_music, -6.0)
	#enemy cue players
	_build_enemy_audio()

func set_music_track(stream: AudioStream, volume_db: float = -6.0):
	_base_db = volume_db
	if stream == null:
		push_warning("AudioManager.set_music_track: null stream")
		return

	if _player.stream != stream:
		_player.stream = stream

#acts as public API (other scripts call only these)
#player calls this
func set_movement_active(active: bool):
	_is_active = active
	_target_db = _base_db if active else fade_out_db

	#start playing when becoming active
	if active and not _player.playing and _player.stream != null:
		_player.pitch_scale = walk_pitch
		_target_pitch = walk_pitch
		_player.play()

#player calls this
func set_sprinting(is_sprinting: bool):
	_target_pitch = sprint_pitch if is_sprinting else walk_pitch

#enemyDirector will call this every frame (or whenever tier changes).
#tier: -1 silent, 0 far, 1 mid, 2 near
func set_enemy_presence_tier(tier: int) -> void:
	#choose audio tier by distance
	if tier == EnemyTier.NEAR:
		_t_breath_pitch = breath_pitch_near
		#background lower, breathing louder + fast
		_set_enemy_targets(near_bed_db, breath_db_near) #far + breathing (FAST + LOUD)
	elif tier == EnemyTier.MID:
		_t_breath_pitch = breath_pitch_mid
		_set_enemy_targets(enemy_active_db, breath_db_mid)  #far + breathing (normal)
	elif tier == EnemyTier.FAR:
		_t_breath_pitch = breath_pitch_mid
		_set_enemy_targets(enemy_active_db, enemy_off_db)   #far only
	else:
		_t_breath_pitch = breath_pitch_mid
		_set_enemy_targets(enemy_off_db, enemy_off_db)      #silent

func force_enemy_intense() -> void:
	#punish: keep base on + force breathing loud/fast
	_t_breath_pitch = breath_pitch_near
	_set_enemy_targets(enemy_active_db, breath_db_near)

func clear_enemy_audio() -> void:
	_set_enemy_targets(enemy_off_db, enemy_off_db)

func _set_enemy_targets(far_db: float, breath_db: float) -> void:
	_t_far = far_db
	_t_breath = breath_db

func _process(delta: float):
	#movement smoothing
	if _player != null:
		_player.pitch_scale = lerp(_player.pitch_scale, _target_pitch, delta * fade_speed)
		_player.volume_db = lerp(_player.volume_db, _target_db, delta * fade_speed)

		#stop completely after fade-out (saves CPU, prevents faint sound)
		if not _is_active and _player.playing and _player.volume_db <= fade_out_db + 0.5:
			_player.stop()

	#enemy smoothing
	_update_enemy_audio(delta)

func _build_enemy_audio() -> void:
	#creating 3 audioplayers for audio cues 
	_p_far = _make_enemy_player(cue_far)
	_p_breath = _make_enemy_player(cue_breath)

func _make_enemy_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = enemy_bus
	p.stream = stream
	p.volume_db = enemy_off_db
	add_child(p)

	#always start if the stream exists (prevents “silent forever” bugs)
	if p.stream != null:
		p.play()
	else:
		push_warning("AudioManager: enemy cue stream is null on bus '%s'" % enemy_bus)

	return p

func _update_enemy_audio(delta: float) -> void:
	#every frame it updates audio fade and pitch 

	#far music - smooth fade-in whenever it starts playing
	if _p_far:
		var far_target_db := _t_far
		var far_should_be_audible := far_target_db > far_retrigger_silence_db
		if far_should_be_audible and not _far_was_audible:
			_far_attack_timer = far_attack_time
			#start from very low volume so it "emerges" instead of popping in
			_p_far.volume_db = min(_p_far.volume_db, far_attack_from_db)

		_far_was_audible = far_should_be_audible
		#if we are in the "attack" ramp, drive volume by time (not by lerp speed)
		if _far_attack_timer > 0.0 and far_should_be_audible:
			_far_attack_timer = max(0.0, _far_attack_timer - delta)
			var t: float = 1.0 - (_far_attack_timer / max(0.001, far_attack_time)) # 0..1
			_p_far.volume_db = lerp(far_attack_from_db, far_target_db, t)
		else:
			#normal fades after the entry, including fade-out when leaving FAR
			_p_far.volume_db = lerp(_p_far.volume_db, far_target_db, delta * enemy_fade_speed)

	if _p_breath:
		_p_breath.volume_db = lerp(_p_breath.volume_db, _t_breath, delta * enemy_fade_speed)
		_p_breath.pitch_scale = lerp(_p_breath.pitch_scale, _t_breath_pitch, delta * pitch_fade_speed)
