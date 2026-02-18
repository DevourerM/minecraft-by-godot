@tool
extends MapStepBase

@export var seed_val: int = 1234

func _init():
	# 局部 ID 定义
	local_id_map = {
		1: "bedrock",
		2: "dirt",
		3: "grass"
	}

func _process_generation(map_data: Dictionary, chunk_size: Vector3i):
	print("  -> [地形层] 正在塑造地貌...")
	
	var noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.02
	
	for x in range(chunk_size.x):
		for z in range(chunk_size.z):
			# 1. 计算地表高度
			var surface_h = int(32 + noise.get_noise_2d(x, z) * 8)
			surface_h = clamp(surface_h, 0, chunk_size.y - 1)
			
			# 2. 垂直填充
			for y in range(surface_h + 1):
				var pos = Vector3i(x, y, z)
				
				if y == 0:
					# 最底层：基岩 (Local 1)
					set_block(map_data, pos, 1)
				elif y == surface_h:
					# 最顶层：草方块 (Local 3)
					set_block(map_data, pos, 3)
				else:
					# 中间全部填泥土 (Local 2)
					# 注意：这里我们不管岩石层，先把所有东西都当泥土填进去
					# 岩石层会在下一个生成器里通过"替换"来实现
					set_block(map_data, pos, 2)
	
	await get_tree().process_frame
