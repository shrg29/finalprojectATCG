extends Control

@export var hover_stream: AudioStream
@export var hover_volume_db: float = -10.0
@export var retrigger_cooldown: float = 0.08 # prevents spam when moving mouse around

var _cooldown := 0.0

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

func _on_mouse_entered() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = retrigger_cooldown

	# fallback to AudioManager default hover if you leave hover_stream empty
	if hover_stream != null:
		AudioManager.play_ui_sfx(hover_stream, hover_volume_db)
	else:
		AudioManager.play_ui_sfx(AudioManager.sfx_ui_hover, hover_volume_db)
