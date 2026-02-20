@tool
extends Node3D

@export var block_type: String = "dirt":
	set(value):
		block_type = value
		if is_inside_tree(): apply_attributes()

var hardness: int = 1
var is_breakable: bool = true
var brightness: float = 0.0
var break_progress: int = 0

@onready var entity_mesh = $"实体/StaticBody3D/MeshInstance3D"

func _ready():
	apply_attributes()

func take_damage(damage_amount: int):
	if not is_breakable: return
	break_progress += damage_amount
	if break_progress >= hardness:
		queue_free() # 彻底清理节点

func _get_property_list():
	var properties = []
	if BlockDatabase and BlockDatabase.block_registry:
		var options = BlockDatabase.block_registry.keys()
		properties.append({
			"name": "block_type", "type": TYPE_STRING,
			"usage": PROPERTY_USAGE_DEFAULT, "hint": PROPERTY_HINT_ENUM,
			"hint_string": ",".join(options)
		})
	return properties

func apply_attributes():
	if not BlockDatabase: return
	var data = BlockDatabase.get_block_data(block_type)
	if not data: return

	hardness = data.get("hardness", 1)
	is_breakable = data.get("is_breakable", true)
	brightness = data.get("brightness", 0.0)

	if not is_instance_valid(entity_mesh): return

	# 强制生成全新材质，100% 杜绝 null pointer crash
	var new_material = ShaderMaterial.new()
	new_material.shader = preload("res://object/block.gdshader")
	
	new_material.set_shader_parameter("texture_top", BlockDatabase.get_texture(data.get("top", "")))
	new_material.set_shader_parameter("texture_side", BlockDatabase.get_texture(data.get("side", "")))
	new_material.set_shader_parameter("texture_bottom", BlockDatabase.get_texture(data.get("bottom", "")))
	new_material.set_shader_parameter("emission_energy", brightness)
	
	entity_mesh.set_surface_override_material(0, new_material)
