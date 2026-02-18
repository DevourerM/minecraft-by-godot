@tool
extends Node3D

@export_group("时间设置")
@export var day_length: float = 10.0
## 0.0=正午, 0.25=日落, 0.5=午夜, 0.75=日出
@export_range(0.0, 1.0) var time_of_day: float = 0.0:
	set(value):
		time_of_day = value
		_update_visuals()

@export var sun_color_gradient: Gradient
@export var sun_intensity_curve: Curve

@export_group("调试")
@export var preview_cycle: bool = false:
	set(value):
		preview_cycle = value
		set_process(true)

var _days_passed: int = 0
var _prev_time: float = 0.0 
var _world_env: WorldEnvironment

func _ready():
	set_process(true)
	_world_env = get_node_or_null("WorldEnvironment")
	_setup_fast_transition_resources() # 使用快速过渡配置
	_disable_procedural_sun()
	_update_moon_texture()

func _process(delta):
	if Engine.is_editor_hint() and not preview_cycle: return
	_prev_time = time_of_day
	time_of_day += delta / day_length
	if time_of_day >= 1.0:
		time_of_day = 0.0
		_prev_time = -0.01
	_update_visuals()
	
	# 日落检测 (0.25 是地平线)
	if _prev_time < 0.25 and time_of_day >= 0.25:
		_on_sunset_trigger()

# --- 核心：配置快速过渡 (30度以内完成) ---
func _setup_fast_transition_resources():
	# 30度对应时间约 0.08。
	# 日落区间: 0.25(开始) -> 0.33(结束)
	# 日出区间: 0.67(开始) -> 0.75(结束)
	
	# 1. 颜色梯度
	sun_color_gradient = Gradient.new()
	sun_color_gradient.remove_point(0)
	sun_color_gradient.remove_point(0)
	
	sun_color_gradient.add_point(0.0, Color(1, 1, 1))      # 正午：纯白
	sun_color_gradient.add_point(0.20, Color(1, 0.9, 0.7)) # 下午：稍微暖色
	sun_color_gradient.add_point(0.25, Color(1, 0.5, 0.2)) # 地平线：金橙
	sun_color_gradient.add_point(0.33, Color(0.1, 0.15, 0.4)) # 30度后：进入深蓝夜色
	sun_color_gradient.add_point(0.67, Color(0.2, 0.1, 0.4))  # 准备日出：深紫
	sun_color_gradient.add_point(0.75, Color(1, 0.4, 0.2)) # 日出地平线：橙红
	sun_color_gradient.add_point(0.80, Color(1, 1, 1))      # 升起后迅速回白
	
	# 2. 亮度曲线
	sun_intensity_curve = Curve.new()
	# 白天
	sun_intensity_curve.add_point(Vector2(0.0, 1.0))
	sun_intensity_curve.add_point(Vector2(0.22, 1.0))
	# 日落：0.25开始，0.33必须降到底
	sun_intensity_curve.add_point(Vector2(0.25, 0.6)) 
	sun_intensity_curve.add_point(Vector2(0.33, 0.1)) # 快速变黑
	# 夜晚
	sun_intensity_curve.add_point(Vector2(0.5, 0.1))
	sun_intensity_curve.add_point(Vector2(0.67, 0.1))
	# 日出：0.67开始，0.75升起
	sun_intensity_curve.add_point(Vector2(0.75, 0.6))
	sun_intensity_curve.add_point(Vector2(0.80, 1.0)) # 快速变亮
	
	print("EnvManager: 已应用30度快速过渡配置")

func _disable_procedural_sun():
	if _world_env and _world_env.environment and _world_env.environment.sky:
		var mat = _world_env.environment.sky.sky_material
		if mat and (mat is ProceduralSkyMaterial):
			mat.sun_angle_max = 0.0

func _update_visuals():
	var pivot = get_node_or_null("Sun_Pivot")
	if not pivot: return
	
	pivot.rotation_degrees.x = (time_of_day * 360.0) - 90.0
	var light = pivot.get_node_or_null("DirectionalLight3D")
	if not light: return

	light.light_color = sun_color_gradient.sample(time_of_day)
	var intensity = sun_intensity_curve.sample(time_of_day)
	light.light_energy = intensity
	
	if _world_env and _world_env.environment:
		# 强制天空背景能量跟随曲线，保持深色氛围
		_world_env.environment.background_energy_multiplier = max(intensity, 0.05)

func _on_sunset_trigger():
	_days_passed += 1
	_update_moon_texture()

func _update_moon_texture():
	var pivot = get_node_or_null("Sun_Pivot")
	if not pivot: return
	var moon = pivot.get_node_or_null("Moon_Visual")
	if not moon or not (moon is AnimatedSprite3D): return
	if not moon.sprite_frames or not moon.sprite_frames.has_animation("phases"): return
	
	if moon.is_playing(): moon.stop()
	var total = moon.sprite_frames.get_frame_count("phases")
	moon.frame = _days_passed % total
