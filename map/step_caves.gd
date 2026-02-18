@tool
extends MapStepBase

@export var seed_val: int = 9999

func _init():
	local_id_map = { 1: "air" }

func _process_generation(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i):
	# print("  -> [结构] 挖掘洞穴...")
	
	var noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.03
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	
	var min_h = 5
	var max_h = 45
	
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			
			# [无缝拼接核心] 计算全局坐标
			var global_x = (chunk_coord.x * chunk_size.x) + x
			var global_z = (chunk_coord.y * chunk_size.z) + z
			
			# 遍历高度区间
			for y in range(1, max_h):
				var pos = Vector3i(x, y, z)
				
				# 1. 采样全局噪声 (保证跨区块连续)
				var val = noise.get_noise_3d(global_x, y, global_z)
				
				# 2. 计算高度衰减 (Fade)
				# 越接近顶端，fade 越大，生成概率越低
				var fade = inverse_lerp(min_h, max_h, y)
				fade = clamp(fade, 0.0, 1.0)
				
				# 3. 动态阈值
				var threshold = 0.6 + (fade * 0.4)
				
				if val > threshold:
					# 只有当这里本来有方块时才挖空
					if map_data.has(pos):
						# 保护地表草皮 (可选优化: 检查是不是 Grass)
						# 这里简单粗暴直接挖
						set_block(map_data, pos, 1) # Air
	
	await get_tree().process_frame
