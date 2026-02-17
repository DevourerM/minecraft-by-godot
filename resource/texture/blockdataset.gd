@tool
extends Node

var texture_path = "res://resource/texture/blocks/"

var block_registry = {
	"dirt": {
		"top": "dirt.png",
		"side": "dirt.png",
		"bottom": "dirt.png",
		"hardness": 1,
		"is_breakable": true,
		"brightness": 0.0   
	},
	"grass": {
		"top": "grass_carried.png",
		"side": "grass_side_carried.png",
		"bottom": "dirt.png",
		"hardness": 1,
		"is_breakable": true,
		"brightness": 0.0
	},
	
	"diamond": {
		"top": "diamond_ore.png",
		"side": "diamond_ore.png",
		"bottom": "diamond_ore.png",
		"hardness": 1,
		"is_breakable": true,
		"brightness": 0.2
	},
	"bedrock": {
		"top": "bedrock.png",
		"side": "bedrock.png",
		"bottom": "bedrock.png",
		"hardness": -1,
		"is_breakable": false,
		"brightness": 0.0
	},
	"stone": {
		"top": "stone.png",
		"side": "stone.png",
		"bottom": "stone.png",
		"hardness": 3,
		"is_breakable": true,
		"brightness": 0.0
	}
}

# 下面的函数保持不变...
func get_texture(file_name: String) -> Texture2D:
	var full_path = texture_path + file_name
	if ResourceLoader.exists(full_path):
		return load(full_path)
	else:
		return null

func get_block_data(block_name: String):
	if block_registry.has(block_name):
		return block_registry[block_name]
	else:
		printerr("错误：注册表中没有这个方块 -> " + block_name)
		return null
