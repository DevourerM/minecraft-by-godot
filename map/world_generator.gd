@tool
extends Node

# --- [常量配置] ---
# 区块大小：决定了世界的最小生成单位 (宽, 高, 长)
# 16x64x16 是经典的 Minecraft 区块比例，适合物理优化
const CHUNK_SIZE = Vector3i(16, 64, 16)

# --- [编辑器属性配置] ---
@export_group("核心设置 (Core Settings)")

## 渲染距离 (Render Distance)
## 以玩家为中心，向外加载的区块半径。
## 例如 4 代表加载 (4*2+1)^2 = 81 个区块。
@export_range(2, 16) var render_distance: int = 4:
	set(value):
		render_distance = value
		# 编辑器模式下打印提示
		if Engine.is_editor_hint():
			print("渲染距离已更改为: ", value)

@export_group("调试与预览 (Debug)")

## 编辑器预览开关
## 勾选后，在编辑器视窗生成预览地图；取消勾选则清空。
@export var generate_preview: bool = false:
	set(value):
		generate_preview = value
		if value and Engine.is_editor_hint():
			start_preview_generation()
		elif not value and Engine.is_editor_hint():
			clear_all_chunks()

# --- [内部变量] ---
@onready var area_node = $"../Area"

# 运行时数据管理
var active_chunks = {}     # 存储已加载区块 { Vector2i(x,z) : Node3D(ChunkRoot) }
var generation_queue = []  # 等待生成的区块坐标队列
var is_generating = false  # 锁：防止同时生成导致数据混乱
var player_node: Node3D = null # 缓存玩家引用

# 资源缓存
var steps: Array[MapStepBase] = [] # 子生成器列表
var base_mesh = BoxMesh.new()      # 用于 MultiMesh 的基础方块网格
var collision_cache_faces = PackedVector3Array() # [优化] 缓存标准立方体的顶点数据

func _ready():
	# 1. 获取所有子生成器 (Step_Terrain, Step_Ores, etc.)
	steps.clear()
	for child in get_children():
		if child is MapStepBase:
			steps.append(child)
	
	# 2. [优化] 预计算标准立方体的面，用于后续合并碰撞体
	# 这样不用对每个方块都重新计算一次 Box 的几何结构
	collision_cache_faces = base_mesh.get_faces()
	
	# 3. 游戏运行时清空编辑器残留
	if not Engine.is_editor_hint():
		clear_all_chunks()

func _process(delta):
	# 编辑器模式下不运行自动加载逻辑
	if Engine.is_editor_hint(): return
	
	# --- 1. 自动查找玩家 ---
	# 如果没有缓存玩家，尝试去 "player" 组里找
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
	
	# --- 2. 计算中心区块 ---
	var center_chunk = Vector2i(0, 0)
	if is_instance_valid(player_node):
		# 将玩家的世界坐标转换为区块坐标
		var px = player_node.global_position.x / CHUNK_SIZE.x
		var pz = player_node.global_position.z / CHUNK_SIZE.z
		center_chunk = Vector2i(floor(px), floor(pz))
	
	# --- 3. 驱动加载系统 ---
	update_chunk_loading(center_chunk)
	process_generation_queue()

# --- [逻辑] 区块加载与卸载管理 ---
func update_chunk_loading(center: Vector2i):
	# A. 卸载超范围的区块 (Render Distance + 2 作为缓冲)
	var remove_threshold = render_distance + 2
	var chunks_to_remove = []
	
	for coord in active_chunks.keys():
		var dx = abs(coord.x - center.x)
		var dz = abs(coord.y - center.y)
		if dx > remove_threshold or dz > remove_threshold:
			chunks_to_remove.append(coord)
	
	for coord in chunks_to_remove:
		unload_chunk(coord)
	
	# B. 将范围内的区块加入等待队列
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var target_coord = center + Vector2i(x, z)
			
			# 如果该区块既未加载，也不在队列中，则添加
			if not active_chunks.has(target_coord) and not target_coord in generation_queue:
				generation_queue.append(target_coord)
	
	# C. 队列排序：离玩家近的优先生成
	if generation_queue.size() > 1:
		generation_queue.sort_custom(func(a, b):
			var dist_a = (a - center).length_squared()
			var dist_b = (b - center).length_squared()
			return dist_a < dist_b
		)

# --- [逻辑] 处理生成队列 (协程) ---
func process_generation_queue():
	# 如果正在生成，或者队列为空，则跳过
	if is_generating or generation_queue.is_empty(): return
	
	is_generating = true
	var coord = generation_queue.pop_front()
	
	# 执行单个区块生成
	await generate_single_chunk(coord)
	
	is_generating = false

# --- [核心] 单个区块生成流程 ---
func generate_single_chunk(coord: Vector2i):
	# 1. 准备数据容器
	var map_data = {}
	
	# 2. 依次执行所有子生成器 (地形 -> 矿石 -> 洞穴)
	var idx = 0
	for step in steps:
		# 传入 coord 用于计算全局噪声坐标
		await step.execute_step(map_data, CHUNK_SIZE, idx, coord)
		idx += 1
	
	# 3. 渲染结果
	render_chunk(coord, map_data)

# --- [渲染] 区块渲染与物理合并 (核心优化点) ---
func render_chunk(coord: Vector2i, map_data: Dictionary):
	# 创建区块根节点 (Node3D)，用于管理该区块的所有内容
	var chunk_root = Node3D.new()
	chunk_root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	# 设置区块在世界的实际位置
	chunk_root.position = Vector3(coord.x * CHUNK_SIZE.x, 0, coord.y * CHUNK_SIZE.z)
	
	area_node.add_child(chunk_root)
	active_chunks[coord] = chunk_root
	
	# --- 数据预处理 ---
	var grouped_pos = {} # 用于视觉渲染: { "dirt": [pos1, pos2], "stone": [...] }
	var all_solid_positions = [] # [新增] 用于物理合并: 收集所有实体方块坐标
	
	for pos in map_data.keys():
		var id_data = map_data[pos]
		
		# [剔除] 如果方块被完全包围，则不渲染也不生成碰撞 (极大提升性能)
		if is_block_hidden_internal(pos, map_data): continue
		
		var gen_idx = id_data.x
		var local_id = id_data.y
		var name = steps[gen_idx].get_block_name_by_local_id(local_id)
		
		# 跳过空气
		if name == "air": continue
		
		# 1. 记录到视觉分组
		if not grouped_pos.has(name): grouped_pos[name] = []
		grouped_pos[name].append(Vector3(pos))
		
		# 2. [新增] 记录到物理列表
		# 这里假设所有非 air 的方块都需要碰撞
		all_solid_positions.append(Vector3(pos))
	
	# --- 视觉层生成 (MultiMesh) ---
	for name in grouped_pos.keys():
		create_multimesh(chunk_root, name, grouped_pos[name])
		await get_tree().process_frame # 防卡顿
	
	# --- 物理层生成 (合并碰撞体) ---
	if all_solid_positions.size() > 0:
		create_merged_chunk_collision(chunk_root, all_solid_positions)

# --- [视觉] 创建 MultiMeshInstance ---
func create_multimesh(parent, block_name, positions):
	var data = BlockDatabase.get_block_data(block_name)
	if not data: return
	
	# 构建材质
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://object/block.gdshader")
	mat.set_shader_parameter("texture_top", BlockDatabase.get_texture(data["top"]))
	mat.set_shader_parameter("texture_side", BlockDatabase.get_texture(data["side"]))
	mat.set_shader_parameter("texture_bottom", BlockDatabase.get_texture(data["bottom"]))
	mat.set_shader_parameter("emission_energy", data.get("brightness", 0.0))
	mat.set_shader_parameter("is_dropped", true) # 使用局部坐标
	
	# 构建 MultiMesh
	var mm = MultiMesh.new()
	mm.mesh = base_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = positions.size()
	
	for i in range(positions.size()):
		var t = Transform3D()
		t.origin = positions[i]
		mm.set_instance_transform(i, t)
		
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.name = "MM_" + block_name
	
	parent.add_child(mmi)

# --- [物理] 创建合并后的碰撞体 (Core Optimization) ---
func create_merged_chunk_collision(parent, positions):
	# 1. 创建唯一的 StaticBody3D
	var body = StaticBody3D.new()
	body.name = "Chunk_Collision_Merged"
	
	# 2. 准备几何数据
	# ConcavePolygonShape3D 需要一个巨大的顶点数组 (每3个点组成一个三角形)
	# 立方体有12个三角形，36个顶点
	var total_vertices = positions.size() * 36
	var all_faces = PackedVector3Array()
	all_faces.resize(total_vertices) # 一次性分配内存，避免频繁扩容
	
	var idx = 0
	# 3. 遍历所有方块，将标准立方体的数据偏移到对应位置
	for pos in positions:
		for v in collision_cache_faces:
			# 顶点坐标 = 标准立方体顶点 + 方块位置
			all_faces[idx] = v + pos
			idx += 1
	
	# 4. 创建凹多边形碰撞形状
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(all_faces)
	
	# 5. 组装节点
	var col_owner = CollisionShape3D.new()
	col_owner.shape = shape
	body.add_child(col_owner)
	
	parent.add_child(body)
	# print("Chunk collision created with %d blocks merged." % positions.size())

# --- [辅助] 卸载区块 ---
func unload_chunk(coord: Vector2i):
	if active_chunks.has(coord):
		var node = active_chunks[coord]
		if is_instance_valid(node):
			node.queue_free() # 连带 MultiMesh 和 MergedCollision 一起删除
		active_chunks.erase(coord)

# --- [辅助] 内部剔除算法 ---
func is_block_hidden_internal(pos: Vector3i, map_data: Dictionary) -> bool:
	# 检查 6 个方向
	var neighbors = [Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]
	for offset in neighbors:
		var n = pos + offset
		# 如果邻居坐标不存在(在区块边界外)，为了安全起见，我们认为它没有被遮挡(可见)
		# (完美方案需要跨区块检测，这里简化处理)
		if not map_data.has(n): return false
		
		var id_data = map_data[n]
		# 如果邻居是空气，则当前方块可见
		if steps[id_data.x].get_block_name_by_local_id(id_data.y) == "air": return false
	
	# 如果所有邻居都存在且不是空气，说明被完全包围，可以剔除
	return true

# --- [编辑器功能] 预览生成 ---
func start_preview_generation():
	clear_all_chunks()
	
	var diameter = render_distance * 2 + 1
	var total = diameter * diameter
	print("=== 开始编辑器预览 (半径: %d | 总区块: %d) ===" % [render_distance, total])
	
	# 生成预览队列
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			generation_queue.append(Vector2i(x, z))
	
	# 从中心开始排序
	generation_queue.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
	
	# 执行生成
	var current = 0
	while not generation_queue.is_empty():
		if not generate_preview: # 允许中途取消
			clear_all_chunks()
			return
			
		await process_generation_queue()
		current += 1
		if current % 10 == 0:
			print("Preview: %d / %d" % [current, total])

# --- [编辑器功能] 清理 ---
func clear_all_chunks():
	if area_node:
		for child in area_node.get_children():
			child.free()
	active_chunks.clear()
	generation_queue.clear()
	is_generating = false
