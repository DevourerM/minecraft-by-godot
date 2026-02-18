@tool
extends MapStepBase

@export var seed_val: int = 1234
@export var frequency: float = 0.01 # 频率越低，地形越平缓，适合大地图

func _init():
	local_id_map = { 1: "bedrock", 2: "dirt", 3: "grass" }

func _process_generation(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i):
	# print("  -> [地形] 计算高度图...")
	
	var noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			# [无缝拼接核心] 
			# 将 局部坐标(0~15) 转换为 全局坐标 (例如 16~31)
			var global_x = (chunk_coord.x * chunk_size.x) + x
			var global_z = (chunk_coord.y * chunk_size.z) + z
			
			# 使用全局坐标采样噪声，保证边缘连续
			var height_noise = noise.get_noise_2d(global_x, global_z)
			
			# 将噪声(-1~1) 映射到高度 (例如 32 +/- 15)
			var surface_h = int(32 + height_noise * 15)
			surface_h = clamp(surface_h, 0, chunk_size.y - 1)
			
			# 垂直填充方块
			for y in range(surface_h + 1):
				var pos = Vector3i(x, y, z)
				
				if y == 0:
					set_block(map_data, pos, 1) # 基岩
				elif y == surface_h:
					set_block(map_data, pos, 3) # 草
				else:
					set_block(map_data, pos, 2) # 泥土
	
	# 模拟一点处理时间，避免瞬间卡顿
	await get_tree().process_frame
