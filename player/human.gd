class_name Player
extends CharacterBody3D

@onready var head = $Head
@onready var interact_ray = $Head/InteractRay 
@onready var steve = $steve
@onready var arm_l = $steve.find_child("*rm_L", true, false)
@onready var arm_r = $steve.find_child("*rm_R", true, false)
@onready var leg_l = $steve.find_child("*eg_L", true, false)
@onready var leg_r = $steve.find_child("*eg_R", true, false)

# 【UI 新增】：绑定我们刚才创建的预览模型
@onready var preview_mesh = $UI/Hotbar/SubViewport/PreviewBlock

@export var walk_speed := 5.0
@export var fly_speed := 10.0
@export var jump_velocity := 9.0 

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_flying := false
var _last_jump_time := 0.0
var _anim_timer := 0.0
var _action_timer := 0.0
const ACTION_DURATION := 0.15

var selection_box: MeshInstance3D

# 【背包新增】：方块库存管理
var available_blocks: Array[String] = []
var current_block_index: int = 0

func _ready():
	_create_selection_box()
	add_to_group("player") 
	_init_hotbar() # 初始化方块列表

# --- [新增：初始化与滚轮切换逻辑] ---
func _init_hotbar():
	# 从数据库自动拉取所有注册的方块
	if BlockDatabase and BlockDatabase.block_registry:
		for key in BlockDatabase.block_registry.keys():
			available_blocks.append(key)
			
		# 确保第一个是 air (空手)
		if "air" in available_blocks:
			available_blocks.erase("air")
		available_blocks.insert(0, "air")
	
	_update_preview()

func _cycle_block(dir: int):
	if available_blocks.is_empty(): return
	# 循环切换
	current_block_index = (current_block_index + dir) % available_blocks.size()
	if current_block_index < 0:
		current_block_index = available_blocks.size() - 1
	_update_preview()

func _update_preview():
	if available_blocks.is_empty() or not preview_mesh: return
	var b_name = available_blocks[current_block_index]
	
	if b_name == "air":
		preview_mesh.hide() # 选空气时隐藏方块
	else:
		preview_mesh.show()
		var data = BlockDatabase.get_block_data(b_name)
		if data:
			# 为 UI 单独生成材质并贴图
			var mat = ShaderMaterial.new()
			mat.shader = preload("res://object/block.gdshader")
			mat.set_shader_parameter("texture_top", BlockDatabase.get_texture(data.get("top","")))
			mat.set_shader_parameter("texture_side", BlockDatabase.get_texture(data.get("side","")))
			mat.set_shader_parameter("texture_bottom", BlockDatabase.get_texture(data.get("bottom","")))
			mat.set_shader_parameter("emission_energy", data.get("brightness", 0.0))
			preview_mesh.material_override = mat
# -----------------------------------

func _physics_process(delta):
	if is_flying: _handle_flying(delta)
	else: _handle_walking(delta)
	move_and_slide()

	if _action_timer > 0:
		_action_timer -= delta
		if arm_r: arm_r.rotation.x = sin((_action_timer / ACTION_DURATION) * PI) * -1.0 

	_update_selection_ray()

func _create_selection_box():
	var mesh = BoxMesh.new()
	mesh.size = Vector3(1.02, 1.02, 1.02)
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_box = MeshInstance3D.new()
	selection_box.mesh = mesh
	selection_box.material_override = mat
	get_tree().root.call_deferred("add_child", selection_box)
	selection_box.hide()

func _update_selection_ray():
	if not interact_ray or not selection_box: return

	if interact_ray.is_colliding():
		var target = interact_ray.get_collider()
		if target is StaticBody3D and "Chunk_Collision" in target.name:
			var hit_point = interact_ray.get_collision_point()
			var normal = interact_ray.get_collision_normal()
			var block_global_pos = (hit_point - normal * 0.01).round()
			selection_box.global_position = block_global_pos
			selection_box.show()
		else:
			selection_box.hide()
	else:
		selection_box.hide()

func _input(event):
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("attack"):
			_action_timer = ACTION_DURATION 
			_try_break_block()
		# 【新增输入】：右键放置，滚轮切换
		elif event.is_action_pressed("build"):
			_action_timer = ACTION_DURATION
			_try_place_block()
		elif event.is_action_pressed("hotbar_next"):
			_cycle_block(1)
		elif event.is_action_pressed("hotbar_prev"):
			_cycle_block(-1)

func _try_break_block():
	if not interact_ray.is_colliding() or not selection_box.visible: return
	var target = interact_ray.get_collider()
	
	if target is StaticBody3D and "Chunk_Collision" in target.name:
		var hit_point = interact_ray.get_collision_point()
		var normal = interact_ray.get_collision_normal()
		var block_global_pos = (hit_point - normal * 0.01).round()
		
		var map_node = get_node_or_null("../map/WorldGenerator") 
		if map_node and map_node.has_method("break_block_at"):
			map_node.break_block_at(block_global_pos)
			
	interact_ray.force_raycast_update()
	_update_selection_ray()

# --- [新增：放置逻辑] ---
func _try_place_block():
	if not interact_ray.is_colliding() or available_blocks.is_empty(): return
	var b_name = available_blocks[current_block_index]
	if b_name == "air": return # 空手不能放方块
	
	var target = interact_ray.get_collider()
	if target is StaticBody3D and "Chunk_Collision" in target.name:
		var hit_point = interact_ray.get_collision_point()
		var normal = interact_ray.get_collision_normal()
		
		# 核心魔法：破坏是往里缩(-0.01)，放置是往法线方向外推(+0.01)
		var place_global_pos = (hit_point + normal * 0.01).round()
		
		var map_node = get_node_or_null("../map/WorldGenerator") 
		if map_node and map_node.has_method("place_block_at"):
			map_node.place_block_at(place_global_pos, b_name)
			
	interact_ray.force_raycast_update()
	_update_selection_ray()
# ------------------------

# --- 以下移动逻辑不变 ---
func _handle_walking(delta):
	if not is_on_floor(): velocity.y -= gravity * delta
	if Input.is_action_just_pressed("jump"):
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - _last_jump_time < 0.3:
			is_flying = true; velocity.y = 0 
		elif is_on_floor(): velocity.y = jump_velocity
		_last_jump_time = current_time
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * walk_speed; velocity.z = direction.z * walk_speed
		if _action_timer <= 0: animate_limbs(delta)
	else:
		velocity.x = move_toward(velocity.x, 0, walk_speed); velocity.z = move_toward(velocity.z, 0, walk_speed)
		if _action_timer <= 0: reset_limbs(delta)

func _handle_flying(delta):
	if Input.is_action_just_pressed("jump"):
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - _last_jump_time < 0.3: is_flying = false
		_last_jump_time = current_time
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * fly_speed; velocity.z = direction.z * fly_speed
		if _action_timer <= 0: animate_limbs(delta)
	else:
		velocity.x = move_toward(velocity.x, 0, fly_speed); velocity.z = move_toward(velocity.z, 0, fly_speed)
		if _action_timer <= 0: reset_limbs(delta)
	var vertical_dir = 0.0
	if Input.is_action_pressed("jump"): vertical_dir += 1.0
	elif Input.is_action_pressed("sneak"): vertical_dir -= 1.0
	velocity.y = move_toward(velocity.y, vertical_dir * fly_speed, fly_speed * 10 * delta)

func animate_limbs(delta: float):
	_anim_timer += delta * 12.0
	var swing = sin(_anim_timer) * 0.6
	if arm_l and arm_r and leg_l and leg_r:
		arm_l.rotation.x = swing; arm_r.rotation.x = -swing
		leg_l.rotation.x = -swing; leg_r.rotation.x = swing

func reset_limbs(delta: float):
	_anim_timer = 0.0
	if arm_l and arm_r and leg_l and leg_r:
		arm_l.rotation.x = lerp(arm_l.rotation.x, 0.0, delta * 15.0)
		arm_r.rotation.x = lerp(arm_r.rotation.x, 0.0, delta * 15.0)
		leg_l.rotation.x = lerp(leg_l.rotation.x, 0.0, delta * 15.0)
		leg_r.rotation.x = lerp(leg_r.rotation.x, 0.0, delta * 15.0)
