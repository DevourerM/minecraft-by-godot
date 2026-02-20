extends Node3D

@export_group("核心场景预加载")
@export var environment_scene: PackedScene
@export var map_scene: PackedScene
@export var player_scene: PackedScene

func _ready():
	print("========== 游戏加载开始 ==========")
	_init_environment()
	_init_map()
	_init_player()
	print("========== 游戏加载完成 ==========")

func _init_environment():
	if environment_scene:
		var env = environment_scene.instantiate()
		add_child(env)
	else:
		var sun = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-60, 45, 0)
		sun.shadow_enabled = true
		add_child(sun)

func _init_map():
	if map_scene:
		var map = map_scene.instantiate()
		map.name = "map" # 固定名称，以便玩家脚本寻找
		add_child(map)

func _init_player():
	if player_scene:
		var player = player_scene.instantiate()
		player.name = "player" # 固定名称
		add_child(player)
		# 在高空生成避免卡顿，由于你的地图可能很高，可以设置到 80 米
		player.global_position = Vector3(0, 80.0, 0) 
	else:
		push_error("[Game] 未配置 player_scene！")
