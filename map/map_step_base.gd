@tool
class_name MapStepBase
extends Node

# 生成器序号 (由管理器分配)
var generator_index: int = -1
# 局部 ID 映射表
var local_id_map: Dictionary = {}

# [核心修改] 增加了 chunk_coord 参数
# map_data: 当前正在生成的这个区块的数据字典
# chunk_size: 区块大小 (例如 16, 64, 16)
# index: 生成器序号
# chunk_coord: 区块的网格坐标，例如 (0,0), (-1, 2)
func execute_step(map_data: Dictionary, chunk_size: Vector3i, index: int, chunk_coord: Vector2i):
	generator_index = index
	# print(">>> [%d] 正在生成区块 %s - 阶段: %s" % [index, chunk_coord, name])
	await _process_generation(map_data, chunk_size, chunk_coord)

# 子类必须重写此函数
func _process_generation(map_data: Dictionary, chunk_size: Vector3i, chunk_coord: Vector2i):
	pass

# 获取方块名
func get_block_name_by_local_id(local_id: int) -> String:
	return local_id_map.get(local_id, "dirt")

# 设置方块 (数据格式: 生成器ID, 局部ID)
func set_block(map_data: Dictionary, pos: Vector3i, local_id: int):
	map_data[pos] = Vector2i(generator_index, local_id)
