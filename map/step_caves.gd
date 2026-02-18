@tool
extends MapStepBase

# 1. 定义我的局部ID表
func _init():
	local_id_map = {
		1: "air" # 空气方块
	}

# 2. 总入口
func _process_generation(map_data: Dictionary, chunk_size: Vector3i):
	print("  -> 洞穴: 正在挖掘...")
	gen_worm_caves(map_data, chunk_size)

# --- 具体生成方法 ---

func gen_worm_caves(map_data: Dictionary, chunk_size: Vector3i):
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.03 # 稍微调高一点频率，让洞穴更像管道
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	
	# 定义洞穴消失的过渡区
	var cave_min_height = 5  # 5层以下完全保持洞穴形状
	var cave_max_height = 45 # 45层以上完全没有洞穴
	
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			# 我们遍历整个可能的洞穴区间
			for y in range(1, cave_max_height):
				var pos = Vector3i(x, y, z)
				
				# 1. 获取原始噪声值 (-1.0 到 1.0)
				# Ridged 模式通常返回值在 -1 到 1 之间，峰值接近 1
				var raw_noise = noise.get_noise_3d(x, y, z)
				
				# 2. 计算高度衰减 (Fade Out)
				# 这是一个 0.0 到 1.0 的值。
				# y 越接近 max_height，fade 就越接近 1.0 (抑制力越强)
				var fade = inverse_lerp(cave_min_height, cave_max_height, y)
				# 限制在 0-1 之间
				fade = clamp(fade, 0.0, 1.0)
				
				# 3. 动态调整阈值
				# 基础阈值是 0.6。
				# 随着 fade 增加(高度上升)，我们需要更高的噪声值才能生成洞穴
				# 比如在底层，阈值是 0.6；在顶层，阈值变成了 0.6 + 0.4 = 1.0 (几乎无法生成)
				var current_threshold = 0.6 + (fade * 0.4)
				
				# 4. 判断生成
				if raw_noise > current_threshold:
					
					# [保护机制]：避免挖穿海底/地表
					# 如果这个位置是水或者沙子(假设有)，或者非常接近地表，再次检查
					# 这里简单判断：如果 map_data 里没有东西(本来就是空)，就不需要操作
					if map_data.has(pos):
						var current_block = map_data[pos]
						
						# 只有当地面是石头(Gen 1, Local 1) 或者 泥土(Gen 0, Local 2) 时才挖
						# 这样可以保护地表的草方块不被挖掉，形成"隐蔽入口"
						# 你也可以去掉这个判断，允许地面塌陷形成入口
						
						set_block(map_data, pos, 1) # Set Local ID 1 (Air)
					
	await get_tree().process_frame
