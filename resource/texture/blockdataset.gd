@tool
extends Node

# 贴图存放的基础路径
var texture_path = "res://resource/texture/blocks/"

# --- 方块注册表 ---
# 现在这里不仅存贴图，还存数值数据
var block_registry = {
	"dirt": {
		"top": "dirt.png",
		"side": "dirt.png",
		"bottom": "dirt.png",
		"hardness": 1,         # 新增：硬度 (比如土是1)
		"is_breakable": true   # 新增：是否可破坏
	},
	"grass": {
		"top": "grass_carried.png",
		"side": "grass_side_carried.png",
		"bottom": "dirt.png",
		"hardness": 1,         # 草方块硬度也是1
		"is_breakable": true
	},
	"stone": {
		"top": "stone.png",
		"side": "stone.png",
		"bottom": "stone.png",
		"hardness": 3,         # 新增：石头比较硬 (比如3)
		"is_breakable": true
	},

}

# 获取纹理 (保持不变)
func get_texture(file_name: String) -> Texture2D:
	var full_path = texture_path + file_name
	if ResourceLoader.exists(full_path):
		return load(full_path)
	else:
		# 这是一个容错处理：如果没图，给个空图防止报错
		return null

# 获取数据 (保持不变，因为我们是把新数据加在字典里返回的)
func get_block_data(block_name: String):
	if block_registry.has(block_name):
		return block_registry[block_name]
	else:
		printerr("错误：注册表中没有这个方块 -> " + block_name)
		return null
