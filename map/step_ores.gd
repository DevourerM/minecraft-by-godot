@tool
extends MapStepBase

func _init():
	# 局部 ID 定义
	local_id_map = {
		1: "stone", 
		2: "coal",
		3: "iron",
		4: "lapis",
		5: "diamond"
	}

func _process_generation(map_data: Dictionary, chunk_size: Vector3i):
	# 1. 岩化：把深层泥土变成石头
	await replace_dirt_with_stone(map_data, chunk_size)
	
	# 2. 矿化：把石头变成矿石
	await gen_coal(map_data, chunk_size)
	await gen_iron(map_data, chunk_size)
	await gen_lapis(map_data, chunk_size)
	await gen_diamond(map_data, chunk_size)

# --- 具体函数 ---

func replace_dirt_with_stone(map_data: Dictionary, chunk_size: Vector3i):
	print("  -> [矿石层] 正在岩化 (泥土 -> 石头)...")
	
	# 我们需要知道每一列的地表高度，才能确定从哪里开始变成石头
	# 简单做法：从上往下扫，找到第一个方块(草/土)，往下数 4 格，之后的土全变石头
	
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			var surface_found = false
			var depth_counter = 0 # 记录离地表有多深
			
			# 从最高空往下扫描
			for y in range(chunk_size.y - 1, 0, -1):
				var pos = Vector3i(x, y, z)
				
				if map_data.has(pos):
					surface_found = true
					depth_counter += 1
					
					# 如果找到了地表，且深度超过 4 层 (即草+3层土)
					if depth_counter > 4:
						# 检查当前方块是不是地形生成器的泥土
						# 地形生成器通常是 Index 0, 泥土是 Local ID 2
						# 但为了通用性，我们只检查它是不是"非基岩"
						var current_block = map_data[pos]
						
						# 如果是地形生成器的泥土 (0, 2)
						if current_block.x == 0 and current_block.y == 2:
							# 替换为我的石头 (Local 1)
							set_block(map_data, pos, 1)

	await get_tree().process_frame

func gen_coal(map_data: Dictionary, chunk_size: Vector3i):
	print("  -> [矿石层] 生成煤炭")
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.08
	
	for pos in map_data.keys():
		var id_data = map_data[pos]
		# 只能替换我自己生成的石头 (GenIndex, LocalID 1)
		if id_data.x == generator_index and id_data.y == 1:
			if pos.y < 50 and noise.get_noise_3d(pos.x, pos.y, pos.z) > 0.35:
				set_block(map_data, pos, 2) # Local 2: Coal

func gen_iron(map_data: Dictionary, chunk_size: Vector3i):
	print("  -> [矿石层] 生成铁矿")
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.1
	
	for pos in map_data.keys():
		var id_data = map_data[pos]
		if id_data.x == generator_index and id_data.y == 1:
			if pos.y < 40 and noise.get_noise_3d(pos.x, pos.y, pos.z) > 0.45:
				set_block(map_data, pos, 3) # Local 3: Iron

func gen_lapis(map_data: Dictionary, chunk_size: Vector3i):
	for pos in map_data.keys():
		var id_data = map_data[pos]
		if id_data.x == generator_index and id_data.y == 1:
			if pos.y < 20 and randf() < 0.02:
				set_block(map_data, pos, 4) # Local 4: Lapis

func gen_diamond(map_data: Dictionary, chunk_size: Vector3i):
	for pos in map_data.keys():
		var id_data = map_data[pos]
		if id_data.x == generator_index and id_data.y == 1:
			if pos.y < 12 and randf() < 0.005: 
				set_block(map_data, pos, 5) # Local 5: Diamond
