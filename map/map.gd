@tool
extends Node3D

# --- 1. 配置区域 ---
# 将宽度改为 32 (按照你的要求)
const CHUNK_SIZE = Vector3i(32, 64, 32) 

# --- [优化] 地形参数调整 ---
@export var surface_seed: int = 1234
@export var surface_base_height: int = 32
# 降低振幅：防止山太高直接切断 (原来是10，改小一点)
@export var surface_amplitude: float = 8.0 
# 降低频率：数值越小，地形越平缓开阔 (原来0.05，改为0.02适合大地图)
@export var surface_frequency: float = 0.02 

# 矿脉配置
@export var ore_seed: int = 5678
@export var ore_frequency: float = 0.08
@export var ore_threshold: float = 0.5 

# 预加载
var block_scene = preload("res://object/block.tscn")
@onready var area_node = $area

# ID 映射
var id_to_name = {
	1: "dirt",
	2: "stone",
	3: "grass",
	4: "bedrock",
	5: "diamond"
}

# 数据存储
var map_data = {}
var terrain_noise = FastNoiseLite.new()
var ore_noise = FastNoiseLite.new()

func _ready():
	# 初始化噪声
	terrain_noise.seed = surface_seed
	terrain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	terrain_noise.frequency = surface_frequency
	
	ore_noise.seed = ore_seed
	ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ore_noise.frequency = ore_frequency
	
	# 开始生成流程
	generate_world_sequence()

# --- [新增] 协程管理器 ---
# 使用 async/await 流程来控制生成顺序，防止卡死
func generate_world_sequence():
	print("1. 开始计算数据...")
	var time_start = Time.get_ticks_msec()
	
	# 数据计算很快，可以直接运行
	generate_data()
	
	print("2. 数据计算完毕，耗时: ", Time.get_ticks_msec() - time_start, "ms")
	print("3. 开始实例化方块 (分帧处理)...")
	
	# 加上 await，调用分帧生成函数
	await generate_view_async()
	
	print("4. 地图加载完成！")

# --- 生成数据 (逻辑不变) ---
func generate_data():
	map_data.clear() # 重新生成时清空旧数据
	
	for x in range(CHUNK_SIZE.x):
		for z in range(CHUNK_SIZE.z):
			var noise_val = terrain_noise.get_noise_2d(x, z)
			var surface_y = int(surface_base_height + (noise_val * surface_amplitude))
			surface_y = clamp(surface_y, 0, CHUNK_SIZE.y - 1)
			
			for y in range(surface_y + 1):
				var block_id = 0
				
				if y == 0: block_id = 4 
				elif y == surface_y: block_id = 3 
				elif y > surface_y - 4: block_id = 1 
				else:
					var ore_val = ore_noise.get_noise_3d(x, y, z)
					if ore_val > ore_threshold and y < 20: 
						block_id = 5 
					else:
						block_id = 2 
				
				if block_id != 0:
					map_data[Vector3i(x, y, z)] = block_id

# --- [核心修改] 分帧生成画面 ---
func generate_view_async():
	# 清理旧节点
	for child in area_node.get_children():
		child.queue_free()
	
	var count = 0
	var batch_size = 30 # 每帧生成的方块数量 (调大加载快但会卡，调小加载慢但丝滑)
	
	for pos in map_data.keys():
		var id = map_data[pos]
		
		# 剔除逻辑
		if is_block_hidden(pos):
			continue
		
		spawn_block(pos, id)
		count += 1
		
		# --- 防卡顿魔法 ---
		# 每生成 batch_size 个方块，就暂停一下，让 CPU 喘口气渲染画面
		if count % batch_size == 0:
			await get_tree().process_frame 
			
	print("实际生成节点数: ", count)

# 实例化 (保持不变)
func spawn_block(pos: Vector3i, id: int):
	var new_block = block_scene.instantiate()
	new_block.position = Vector3(pos)
	area_node.add_child(new_block)
	
	var block_name = id_to_name.get(id, "dirt")
	if "block_type" in new_block:
		new_block.block_type = block_name

# 剔除逻辑 (保持不变)
func is_block_hidden(pos: Vector3i) -> bool:
	var neighbors = [
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]
	for offset in neighbors:
		var neighbor_pos = pos + offset
		if not map_data.has(neighbor_pos):
			return false 
	return true
