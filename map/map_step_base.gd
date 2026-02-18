@tool
class_name MapStepBase
extends Node

# 生成器序号 (由 WorldGenerator 分配)
var generator_index: int = -1
# 局部 ID 映射
var local_id_map: Dictionary = {}

func execute_step(map_data: Dictionary, chunk_size: Vector3i, index: int):
	generator_index = index
	print(">>> [%d] %s 开始执行..." % [index, name])
	await _process_generation(map_data, chunk_size)

func _process_generation(map_data: Dictionary, chunk_size: Vector3i):
	pass

func get_block_name_by_local_id(local_id: int) -> String:
	return local_id_map.get(local_id, "dirt")

# [核心] 多维数组写入
# 写入格式: Vector2i(生成器序号, 局部ID)
func set_block(map_data: Dictionary, pos: Vector3i, local_id: int):
	map_data[pos] = Vector2i(generator_index, local_id)
