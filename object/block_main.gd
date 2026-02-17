@tool
extends Node3D

# --- 属性 ---
# 1. 方块类型
var block_type: String = "dirt":
	set(value):
		block_type = value
		if is_inside_tree():
			apply_attributes()

# 2. 游戏属性 (从数据库读取)
var is_breakable: bool = true 
var hardness: int = 1         

# 3. 破坏进度 (新添加)
var break_progress: int = 0
var is_broken: bool = false # 标记是否已经碎了，防止重复破碎

# --- 节点引用 ---
# 注意：我们要控制整个“实体”和“掉落”节点的可见性，不仅仅是网格
@onready var entity_node = $"实体"
@onready var drop_node = $"掉落"

# 网格引用仅用于贴图
@onready var entity_mesh = $"实体/StaticBody3D/MeshInstance3D"
@onready var drop_mesh = $"掉落/Area3D/MeshInstance3D"

func _ready():
	# 1. 应用贴图和数据
	apply_attributes()
	
	# 2. 初始化可见性状态 (新添加)
	# 游戏开始时：实体可见，掉落物隐藏
	if not Engine.is_editor_hint():
		entity_node.visible = true
		drop_node.visible = false
		break_progress = 0
		is_broken = true

func _process(delta):
	# 掉落物旋转逻辑 (Z轴)
	# 修改：只有当方块被破坏(掉落物显示)时才旋转，节省性能
	if is_broken and not Engine.is_editor_hint():
		drop_node.rotate_y(2.0 * delta)

# --- 核心功能：接收破坏 (新添加) ---
# 这个函数以后会由角色的脚本来调用
func take_damage(damage_amount: int):
	# 如果不可破坏(基岩) 或者 已经碎了，直接忽略
	if not is_breakable or is_broken:
		return

	# 1. 累计破坏度
	break_progress += damage_amount
	print("方块: ", block_type, " | 当前进度: ", break_progress, "/", hardness)

	# 2. 检查是否达到硬度阈值
	if break_progress >= hardness:
		break_block()

# --- 核心功能：破碎逻辑 ---
func break_block():
	is_broken = true
	
	# 切换可见性
	entity_node.visible = false # 隐藏方块实体
	drop_node.visible = true    # 显示掉落物
	
	print("方块破碎！生成掉落物。")
	
	# (可选) 可以在这里播放破碎音效或粒子效果

# --- 编辑器下拉菜单 ---
func _get_property_list():
	var properties = []
	if BlockDatabase and BlockDatabase.block_registry:
		var options = BlockDatabase.block_registry.keys()
		var hint_string = ",".join(options)
		properties.append({
			"name": "block_type",
			"type": TYPE_STRING,
			"usage": PROPERTY_USAGE_DEFAULT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": hint_string
		})
	return properties

# --- 应用材质和数值 ---
func apply_attributes():
	var data = BlockDatabase.get_block_data(block_type)
	if not data: return

	# 读取数值
	hardness = data.get("hardness", 1) 
	is_breakable = data.get("is_breakable", true)

	# 读取纹理
	var tex_top = BlockDatabase.get_texture(data["top"])
	var tex_side = BlockDatabase.get_texture(data["side"])
	var tex_bottom = BlockDatabase.get_texture(data["bottom"])
	
	# 应用材质
	_apply_material_to_mesh(entity_mesh, tex_top, tex_side, tex_bottom)
	_apply_material_to_mesh(drop_mesh, tex_top, tex_side, tex_bottom)

# 辅助函数
func _apply_material_to_mesh(target_mesh: MeshInstance3D, t_top, t_side, t_bottom):
	if target_mesh == null: return
	var material = target_mesh.get_surface_override_material(0)
	if material == null: material = target_mesh.get_active_material(0)
	if material:
		material = material.duplicate()
		target_mesh.set_surface_override_material(0, material)
		material.set_shader_parameter("texture_top", t_top)
		material.set_shader_parameter("texture_side", t_side)
		material.set_shader_parameter("texture_bottom", t_bottom)
