@tool
extends Node

# 建议改为 16，基于节点的物理引擎扛不住太大
const CHUNK_SIZE = Vector3i(32, 64, 32)
@onready var area_node = $"../Area"

# 编辑器按钮
@export var generate_map: bool = false:
	set(value):
		generate_map = value
		if value and Engine.is_editor_hint():
			start_pipeline()

var map_data = {}
var steps: Array[MapStepBase] = []

# 缓存基础网格 (所有方块共用一个立方体模型)
var base_mesh = BoxMesh.new()

func _ready():
	if not Engine.is_editor_hint():
		start_pipeline()

func start_pipeline():
	if not area_node: area_node = get_node_or_null("../Area")
	if not area_node: return

	print("=== MultiMesh 流水线启动 ===")
	steps.clear()
	map_data.clear()
	
	var idx = 0
	for child in get_children():
		if child is MapStepBase:
			steps.append(child)
			await child.execute_step(map_data, CHUNK_SIZE, idx)
			idx += 1
			
	print("=== 数据生成完毕，开始极速渲染 ===")
	render_with_multimesh()

# --- [核心优化] 使用 MultiMesh 渲染 ---
func render_with_multimesh():
	# 1. 清理旧节点
	for child in area_node.get_children():
		child.free()
	
	# 2. 数据分类：把所有坐标按"方块名字"分类
	# 格式: { "stone": [Vector3(...), Vector3(...)], "dirt": [...] }
	var grouped_positions = {}
	
	for pos in map_data.keys():
		var id_data = map_data[pos]
		
		# 剔除逻辑 (空气或被遮挡)
		if is_air(id_data) or is_block_hidden(pos): 
			continue
			
		var gen_idx = id_data.x
		var local_id = id_data.y
		var block_name = steps[gen_idx].get_block_name_by_local_id(local_id)
		
		if block_name == "air": continue
		
		if not grouped_positions.has(block_name):
			grouped_positions[block_name] = []
		grouped_positions[block_name].append(Vector3(pos))

	# 3. 为每种方块创建一个 MultiMeshInstance
	for block_name in grouped_positions.keys():
		var positions = grouped_positions[block_name]
		if positions.is_empty(): continue
		
		create_multimesh_chunk(block_name, positions)
		
		# 简单的防卡顿
		await get_tree().process_frame

# 创建单个种类的 MultiMesh
func create_multimesh_chunk(block_name: String, positions: Array):
	# A. 准备材质
	var data = BlockDatabase.get_block_data(block_name)
	if not data: return
	
	# 获取贴图
	var tex_top = BlockDatabase.get_texture(data["top"])
	var tex_side = BlockDatabase.get_texture(data["side"])
	var tex_bottom = BlockDatabase.get_texture(data["bottom"])
	var brightness = data.get("brightness", 0.0)
	
	# 创建材质 (StandardMaterial3D 或 ShaderMaterial)
	# 为了配合你的 Shader，我们需要在这里动态创建一个 ShaderMaterial
	# 注意：这里我们假设你有预加载好的 Shader 文件
	var material = ShaderMaterial.new()
	material.shader = preload("res://object/block.gdshader") # 确保路径对！
	material.set_shader_parameter("texture_top", tex_top)
	material.set_shader_parameter("texture_side", tex_side)
	material.set_shader_parameter("texture_bottom", tex_bottom)
	material.set_shader_parameter("emission_energy", brightness)
	# 关键：开启局部坐标模式，因为 MultiMesh 的 instance 坐标转换
	material.set_shader_parameter("is_dropped", true) 
	
	# B. 创建 MultiMesh
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = base_mesh # 共用一个 BoxMesh
	multimesh.instance_count = positions.size()
	
	# C. 填充坐标
	for i in range(positions.size()):
		var t = Transform3D()
		t.origin = positions[i]
		multimesh.set_instance_transform(i, t)
	
	# D. 创建节点放入场景
	var mm_instance = MultiMeshInstance3D.new()
	mm_instance.multimesh = multimesh
	mm_instance.material_override = material # 赋予材质
	mm_instance.name = "MM_" + block_name
	
	# E. [物理碰撞] 
	# MultiMesh 没有碰撞，我们需要加一个简单的静态体
	# 这种方式比生成几千个节点稍微好点，但依然重。
	# 为了演示不闪退，这里先做简单的碰撞处理：
	create_static_collision(mm_instance, positions)
	
	area_node.add_child(mm_instance)
	print("渲染层: %s | 数量: %d" % [block_name, positions.size()])

# 为 MultiMesh 添加碰撞 (简化版)
func create_static_collision(parent, positions):
	# 警告：如果方块太多，这里依然会卡。
	# 最完美的方案是使用 PhysicsServer3D，但代码量很大。
	# 这里我们采用折中方案：只生成碰撞体，不生成 Mesh
	for pos in positions:
		var col_body = StaticBody3D.new()
		var col_shape = CollisionShape3D.new()
		var shape = BoxShape3D.new() # 简单的盒子碰撞
		
		col_shape.shape = shape
		col_body.position = pos # 相对于 area_node
		col_body.add_child(col_shape)
		parent.add_child(col_body)

# --- 辅助函数保持不变 ---
func is_block_hidden(pos: Vector3i) -> bool:
	var neighbors = [Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]
	for offset in neighbors:
		var n_pos = pos + offset
		if not map_data.has(n_pos): return false
		var n_id = map_data[n_pos]
		if is_air(n_id): return false
	return true

func is_air(id_data: Vector2i) -> bool:
	var gen_idx = id_data.x
	var local_id = id_data.y
	if gen_idx < steps.size():
		var name = steps[gen_idx].get_block_name_by_local_id(local_id)
		if name == "air": return true
	return false
