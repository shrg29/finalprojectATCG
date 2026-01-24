extends ColorRect

@export var max_intensity := 0.55  # keep < 0.7 or it becomes too bright
@export var fade_speed := 10.0     # how fast it fades in/out
@export var scroll_speed := 1.5    # vertical crawl speed
@export var jitter_amount := 0.003 # small screen jitter

var _active := false
var _intensity := 0.0
var _time := 0.0

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = _shader_code()
	visible = false

func set_flicker_active(on: bool) -> void:
	_active = on
	if on:
		visible = true

func _process(delta: float) -> void:
	_time += delta
	var target := max_intensity if _active else 0.0
	_intensity = lerp(_intensity, target, delta * fade_speed)

	# Hide when fully off
	if not _active and _intensity <= 0.01:
		visible = false

	var sm := material as ShaderMaterial
	sm.set_shader_parameter("u_intensity", _intensity)
	sm.set_shader_parameter("u_time", _time)
	sm.set_shader_parameter("u_scroll", scroll_speed)
	sm.set_shader_parameter("u_jitter", jitter_amount)

func _shader_code() -> String:
	return """
shader_type canvas_item;

uniform float u_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float u_time = 0.0;
uniform float u_scroll = 1.5;
uniform float u_jitter = 0.003;

float hash(vec2 p){
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f*f*(3.0-2.0*f);
	return mix(a, b, u.x) + (c - a)*u.y*(1.0 - u.x) + (d - b)*u.x*u.y;
}

void fragment(){
	// UV with subtle jitter (feels like interference, not lightning)
	vec2 uv = UV;
	float jx = (noise(vec2(u_time * 12.0, uv.y * 40.0)) - 0.5) * u_jitter;
	float jy = (noise(vec2(uv.x * 40.0, u_time * 9.0)) - 0.5) * (u_jitter * 0.6);
	uv += vec2(jx, jy);

	// moving noise (static crawl)
	float n = noise(vec2(uv.x * 220.0, uv.y * 220.0 + u_time * u_scroll * 60.0));

	// scanlines
	float scan = 0.65 + 0.35 * sin((uv.y + u_time * 0.15) * 900.0);

	// occasional thicker bars like in your reference
	float bar = smoothstep(0.98, 1.0, noise(vec2(u_time * 2.5, uv.y * 2.0)));

	// grayscale static, keep it darker (avoid white flashes)
	float v = (n * 0.75 + 0.25) * scan;
	v = mix(v, v * 0.35, bar); // dark bar overlay

	// final alpha scales with intensity, but clamp to avoid lightning-white
	float a = clamp(u_intensity * 0.85, 0.0, 0.85);

	COLOR = vec4(vec3(v), a);
}
""";
