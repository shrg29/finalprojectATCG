extends Node

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

func _ready():
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)

func set_music_track(stream: AudioStream, volume_db: float = -6.0):
	_base_db = volume_db
	if stream == null:
		push_warning("AudioManager.set_music_track: null stream")
		return

	if _player.stream != stream:
		_player.stream = stream

func set_movement_active(active: bool):
	_is_active = active
	_target_db = _base_db if active else fade_out_db

	#start playing when becoming active
	if active and not _player.playing and _player.stream != null:
		_player.pitch_scale = walk_pitch
		_target_pitch = walk_pitch
		_player.play()

func set_sprinting(is_sprinting: bool):
	_target_pitch = sprint_pitch if is_sprinting else walk_pitch
	
func _process(delta: float):
	if _player == null:
		return

	_player.pitch_scale = lerp(_player.pitch_scale, _target_pitch, delta * fade_speed)
	_player.volume_db = lerp(_player.volume_db, _target_db, delta * fade_speed)

	#stop completely after fade-out (saves CPU, prevents faint sound)
	if not _is_active and _player.playing and _player.volume_db <= fade_out_db + 0.5:
		_player.stop()
