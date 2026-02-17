@tool
extends Node3D

# ==========================================
# 1. 核心配置 (通过数据库读取)
# ==========================================
# 方块类型 (在编辑器面板通过下拉菜单选择)
var block_type: String = "dirt":
	set(value):
		block_type = value
		# 编辑器内修改类型时，立即刷新外观
		if is_inside_tree():
			apply_attributes()

# 游戏数值 (从数据库加载，供外部读取)
var hardness: int = 1           # 硬度：需要多少伤害才能破坏
var is_breakable: bool = true   # 可破坏性：基岩为 false
var brightness: float = 0.0     # 发光亮度：0.0~16.0，配合 Environment 的 Glow 使用

# ==========================================
# 2. 运行时状态
# ==========================================
var break_progress: int = 0     # 当前累积的破坏度
var is_broken: bool = false     # 标记是否已破碎 (防止重复触发掉落)

# ==========================================
# 3. 节点引用
# ==========================================
# 父节点引用：用于控制整体显示/隐藏
@onready var entity_node = $"实体"
@onready var drop_node = $"掉落"

# 网格引用：用于设置材质和Shader参数
@onready var entity_mesh = $"实体/StaticBody3D/MeshInstance3D"
@onready var drop_mesh = $"掉落/Area3D/MeshInstance3D"

# ==========================================
# 4. 生命周期
# ==========================================
func _ready():
	# --- 修复核心：初始化状态 ---
	# 无论是在编辑器还是游戏运行，生成方块时必须强制：
	# 1. 实体可见
	# 2. 掉落物隐藏 (解决 Z-fighting 条纹闪烁问题)
	entity_node.visible = true
	drop_node.visible = false
	break_progress = 0
	is_broken = false
	
	# 3. 这里的 apply_attributes 必须在设置完 visible 之后调用
	# 确保材质被正确加载
	apply_attributes()

func _process(delta):
	# 视觉效果：掉落物旋转
	# 优化：只有当方块"碎了"(is_broken)且在游戏运行时才计算旋转
	if is_broken and not Engine.is_editor_hint():
		# 按照要求：以 Z 轴为旋转轴
		drop_node.rotate_z(2.0 * delta)

# ==========================================
# 5. 游戏逻辑接口 (供玩家/工具调用)
# ==========================================
# 接收伤害
func take_damage(damage_amount: int):
	# 校验：不可破坏或已破碎则忽略
	if not is_breakable or is_broken:
		return

	# 1. 累积进度
	break_progress += damage_amount
	# print("DEBUG: 方块 %s 受伤 | 进度: %d/%d" % [block_type, break_progress, hardness])

	# 2. 判定破坏
	if break_progress >= hardness:
		break_block()

# 执行破坏逻辑
func break_block():
	is_broken = true
	
	# 切换显示状态：隐藏实体 -> 显示掉落物
	entity_node.visible = false
	drop_node.visible = true
	
	# TODO: 在此处添加粒子特效或破碎音效
	# print("DEBUG: 方块 %s 破碎！" % block_type)

func _reset_state():
	entity_node.visible = true
	drop_node.visible = false
	break_progress = 0
	is_broken = false
	# 强制停止旋转
	drop_node.rotation = Vector3.ZERO

# ==========================================
# 6. 编辑器工具 (生成属性面板)
# ==========================================
func _get_property_list():
	var properties = []
	# 从数据库获取所有注册的方块名，生成下拉菜单
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

# ==========================================
# 7. 外观与数据应用 (核心函数)
# ==========================================
func apply_attributes():
	# 1. 安全检查：确保数据库存在且能找到该方块
	var data = BlockDatabase.get_block_data(block_type)
	if not data:
		printerr("BlockManager Error: 未知方块类型 -> ", block_type)
		return

	# 2. 同步数值属性 (使用 .get 提供默认值，防止数据库漏填报错)
	hardness = data.get("hardness", 1)
	is_breakable = data.get("is_breakable", true)
	brightness = data.get("brightness", 0.0) # 读取亮度

	# 3. 获取纹理资源
	var tex_top = BlockDatabase.get_texture(data.get("top", ""))
	var tex_side = BlockDatabase.get_texture(data.get("side", ""))
	var tex_bottom = BlockDatabase.get_texture(data.get("bottom", ""))
	
	# 4. 应用到材质 (分别处理实体和掉落物)
	_update_mesh_material(entity_mesh, tex_top, tex_side, tex_bottom, brightness)
	_update_mesh_material(drop_mesh, tex_top, tex_side, tex_bottom, brightness)

# 辅助函数：更新单个网格的材质参数
func _update_mesh_material(target_mesh: MeshInstance3D, t_top, t_side, t_bottom, t_brightness):
	if target_mesh == null:
		return
	
	# 获取当前材质 (优先取覆盖材质)
	var material = target_mesh.get_surface_override_material(0)
	if material == null:
		material = target_mesh.get_active_material(0)
	
	if material:
		# 关键：复制材质，确保修改不会影响到其他同类方块
		material = material.duplicate()
		target_mesh.set_surface_override_material(0, material)
		
		# 设置 Shader 参数：贴图
		material.set_shader_parameter("texture_top", t_top)
		material.set_shader_parameter("texture_side", t_side)
		material.set_shader_parameter
