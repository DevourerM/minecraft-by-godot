@tool
extends MapStepBase

# 初始化局部 ID 映射表
func _init():
	local_id_map = {
		1: "stone", 
		2: "coal",
		3: "iron",
		4: "lapis",
		5: "diamond"
	}

# 主入口：依次调用各个生成步骤
func _process_generation(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i):
	# 1. 岩化：把深层泥土变成石头 (无需全局坐标)
	await replace_dirt_with_stone(map_data, chunk_size)
	
	# 2. 矿化：生成各种矿石 (传入 chunk_coord 以保证跨区块连续)
	await gen_coal(map_data, chunk_size, chunk_coord)
	await gen_iron(map_data, chunk_size, chunk_coord)
	await gen_lapis(map_data, chunk_size, chunk_coord)
	await gen_diamond(map_data, chunk_size, chunk_coord)

# --- 岩化处理 (保持不变) ---
# 作用：扫描地形，将地表下一定深度的泥土替换为石头
func replace_dirt_with_stone(map_data: Dictionary, chunk_size: Vector3i):
	# print("  -> [矿石层] 正在岩化...")
	var max_depth = randi_range(2 , 6)
	var rock_start_depth =max_depth # 离地表多少格开始变石头
	
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			var depth = 0
			# 从顶到底扫描
			for y in range(chunk_size.y - 1, 0, -1):
				var pos = Vector3i(x, y, z)
				if map_data.has(pos):
					depth += 1
					# 如果离地表够深，且是 Terrain 生成器的泥土(Gen 0, Local 2)
					if depth > rock_start_depth:
						var block = map_data[pos]
						if block.x == 0 and block.y == 2:
							set_block(map_data, pos, 1) # 替换为 Local 1 (Stone)

# --- 煤炭生成函数 ---
func gen_coal(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i):
	# print("  -> [矿石层] 生成煤炭")
	
	# === [煤炭配置] ===
	var my_local_id = 2      # 煤炭在本生成器中的 ID
	var max_height = 55      # 最高生成高度 (煤炭分布很广)
	var rarity = 0.35        # 稀有度阈值 (-1到1)。数值越小越常见，越大越稀有。
	var noise_freq = 0.05    # 矿团大小。数值越小，矿团越大且连片；数值越大，矿越碎。
	# =================
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()     # 随机种子
	noise.frequency = noise_freq
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX # Simplex 适合生成团状矿脉
	
	_apply_ore_noise(map_data, chunk_size, chunk_coord, noise, max_height, rarity, my_local_id)

# --- 铁矿生成函数 ---
func gen_iron(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i):
	# print("  -> [矿石层] 生成铁矿")
	
	# === [铁矿配置] ===
	var my_local_id = 3
	var max_height = 40      # 比煤炭生成得低一些
	var rarity = 0.45        # 比煤炭稀有 (阈值更高)
	var noise_freq = 0.08    # 矿团比煤炭稍微小一点 (频率更高)
	# =================
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = noise_freq
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	
	_apply_ore_noise(map_data, chunk_size, chunk_coord, noise, max_height, rarity, my_local_id)

# --- 青金石生成函数 ---
func gen_lapis(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i):
	# print("  -> [矿石层] 生成青金石")
	
	# === [青金石配置] ===
	var my_local_id = 4
	var max_height = 25      # 深层矿物
	var rarity = 0.55        # 比较稀有
	var noise_freq = 0.1     # 矿团较小
	# =================
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = noise_freq
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	
	_apply_ore_noise(map_data, chunk_size, chunk_coord, noise, max_height, rarity, my_local_id)

# --- 钻石生成函数 ---
func gen_diamond(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i):
	# print("  -> [矿石层] 生成钻石")
	
	# === [钻石配置] ===
	var my_local_id = 5
	var max_height = 12      # 最底层矿物
	var rarity = 0.65        # 非常稀有 (阈值很高，只有噪声峰值处才会生成)
	var noise_freq = 0.12    # 很小的团簇
	# =================
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = noise_freq
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	
	_apply_ore_noise(map_data, chunk_size, chunk_coord, noise, max_height, rarity, my_local_id)


# --- [内部工具函数] 通用噪声应用逻辑 ---
# 既然所有矿石的生成逻辑是一样的（都是基于噪声替换石头），我提取了一个私有函数来避免代码重复
func _apply_ore_noise(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i, noise: FastNoiseLite, max_h: int, rarity: float, target_id: int):
	
	for pos in map_data.keys():
		var id_data = map_data[pos]
		
		# 核心检查：只替换 "本生成器生成的石头 (Local ID 1)"
		# 这样不会覆盖掉其他的矿石，也不会把土变成矿
		if id_data.x == generator_index and id_data.y == 1:
			
			# 1. 高度检查 (局部 y 坐标)
			if pos.y > max_h: 
				continue
				
			# 2. 计算全局坐标 (Global X, Z) 用于无缝噪声
			var global_x = (chunk_coord.x * chunk_size.x) + pos.x
			var global_z = (chunk_coord.y * chunk_size.z) + pos.z
			
			# 3. 获取噪声值 (使用 3D 噪声以形成球状矿团)
			var val = noise.get_noise_3d(global_x, pos.y, global_z)
			
			# 4. 稀有度检查
			if val > rarity:
				set_block(map_data, pos, target_id)
				
	# 模拟耗时操作，防止主线程卡死
	await get_tree().process_frame
