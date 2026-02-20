extends Node3D

@export_group("云层设置")
# 【核心新增】：在右侧面板暴露出一个槽位，让你直接拖入或新建 Shader！
@export var cloud_shader: Shader 

@export var cloud_height: float = 120.0
@export var cloud_speed: Vector2 = Vector2(2.0, 1.0)
@export var cloud_size: float = 12.0
@export var grid_radius: int = 40
@export var coverage: float = 0.45

@onready var multi_mesh_instance = $CloudMeshes

var noise = FastNoiseLite.new()
var base_mesh = BoxMesh.new()
var drift_offset = Vector2.ZERO
var last_update_pos = Vector2(999999, 999999)
var player_node: Node3D = null

# 用于持有 Shader 材质的引用
var cloud_material: ShaderMaterial

# 尝试寻找昼夜循环控制器
# 假设你的昼夜脚本挂载的节点名字叫 "EnvManager" 或者类似的，且是当前节点的兄弟或父级
@onready var env_manager = get_parent()

func _ready():
	if env_manager == null:
		printerr("CloudSystem: 警告！未找到 'EnvManager' 节点，云朵将不会随昼夜变化。请检查路径。")

	# 1. 初始化自然噪声生成器 (决定云的形状)
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.04

	# 2. 设置云的基础方块形状
	base_mesh.size = Vector3(cloud_size + 0.1, cloud_size * 0.6, cloud_size + 0.1)

	# 3. 新建材质对象
	cloud_material = ShaderMaterial.new()

	# 【应用你配置的 Shader】
	if cloud_shader != null:
		cloud_material.shader = cloud_shader
	else:
		printerr("CloudSystem: 错误！请选中 CloudSystem 节点，在右侧面板的 Cloud Shader 中新建或拖入着色器！")

	# 传递基础颜色参数 (带一点点蓝的白，80%不透明度)
	cloud_material.set_shader_parameter("base_color", Color(0.98, 0.98, 1.0, 0.8))

	# 把材质赋给网格
	base_mesh.material = cloud_material

	# 4. 初始化底层 MultiMesh
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = base_mesh
	multi_mesh_instance.multimesh = mm

func _process(delta):
	# ==================================================
	# 每帧更新 Shader 的昼夜因子 (根据环境光变化)
	# ==================================================
	if cloud_material and is_instance_valid(env_manager):
		var current_sun_intensity = 1.0
		# 尝试从你的昼夜管理脚本中获取阳光强度曲线采样
		if "sun_intensity_curve" in env_manager and "time_of_day" in env_manager:
			if env_manager.sun_intensity_curve:
				current_sun_intensity = env_manager.sun_intensity_curve.sample(env_manager.time_of_day)
		
		# 传给 Shader
		cloud_material.set_shader_parameter("day_night_factor", current_sun_intensity)


	# 计算风吹动的偏移量
	drift_offset += cloud_speed * delta

	# 自动寻找玩家
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0: player_node = players[0]

	var center_pos = Vector2.ZERO
	if is_instance_valid(player_node):
		center_pos = Vector2(player_node.global_position.x, player_node.global_position.z)

	# 计算带有风向偏移的"逻辑中心点"
	var logical_center = center_pos - drift_offset
	var grid_x = round(logical_center.x / cloud_size)
	var grid_z = round(logical_center.y / cloud_size)
	var current_grid_pos = Vector2(grid_x, grid_z)

	# 只有当风吹过了一个方块的距离，或者玩家走过了一个方块的距离时，才刷新网格
	if current_grid_pos != last_update_pos:
		_update_clouds(current_grid_pos)
		last_update_pos = current_grid_pos

	# 让整个云层物理节点平滑移动
	multi_mesh_instance.global_position.x = drift_offset.x
	multi_mesh_instance.global_position.y = cloud_height
	multi_mesh_instance.global_position.z = drift_offset.y

# 极速重绘云层
func _update_clouds(center_grid: Vector2):
	var valid_positions = PackedVector3Array()
	
	# 扫描玩家头顶的巨大网格
	for x in range(-grid_radius, grid_radius):
		for z in range(-grid_radius, grid_radius):
			var sample_x = center_grid.x + x
			var sample_z = center_grid.y + z
			
			# 从噪声图中采样
			var n = noise.get_noise_2d(sample_x, sample_z)
			var normalized = (n + 1.0) / 2.0
			
			# 如果密度达标，就产生一块云
			if normalized > (1.0 - coverage):
				var world_x = sample_x * cloud_size
				var world_z = sample_z * cloud_size
				valid_positions.append(Vector3(world_x, 0, world_z))

	# 瞬间推入显卡渲染
	var mm = multi_mesh_instance.multimesh
	mm.instance_count = valid_positions.size()
	for i in range(valid_positions.size()):
		var t = Transform3D(Basis(), valid_positions[i])
		mm.set_instance_transform(i, t)
