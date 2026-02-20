@tool
extends Node

const CHUNK_SIZE = Vector3i(16, 64, 16)

@export_group("核心设置")
@export_range(2, 16) var render_distance: int = 4:
	set(value):
		render_distance = value
		if Engine.is_editor_hint(): print("渲染距离已更改为: ", value)

@export_group("调试与预览")
@export var generate_preview: bool = false:
	set(value):
		generate_preview = value
		if value and Engine.is_editor_hint(): start_preview_generation()
		elif not value and Engine.is_editor_hint(): clear_all_chunks()

@onready var area_node = $"../Area" if has_node("../Area") else self

var active_chunks = {}     
var generation_queue = []  
var generating_chunks = [] # 线程安全锁：防止重叠生成
var is_generating = false  
var player_node: Node3D = null

# 【全地图数据总管】：完全由字典来掌控世界的生死
var chunk_block_data = {} 

var steps: Array = [] 
var base_mesh = BoxMesh.new()      
var collision_cache_faces = PackedVector3Array()

func _ready():
	steps.clear()
	for child in get_children():
		if child.has_method("execute_step"): steps.append(child)
	collision_cache_faces = base_mesh.get_faces()
	if not Engine.is_editor_hint(): clear_all_chunks()

func _process(delta):
	if Engine.is_editor_hint(): return
	
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0: player_node = players[0]
			
	var center_chunk = Vector2i(0, 0)
	if is_instance_valid(player_node):
		var px = player_node.global_position.x / CHUNK_SIZE.x
		var pz = player_node.global_position.z / CHUNK_SIZE.z
		center_chunk = Vector2i(floor(px), floor(pz))
		
	update_chunk_loading(center_chunk)
	process_generation_queue()

func update_chunk_loading(center: Vector2i):
	var remove_threshold = render_distance + 2
	var chunks_to_remove = []
	for coord in active_chunks.keys():
		if abs(coord.x - center.x) > remove_threshold or abs(coord.y - center.y) > remove_threshold:
			chunks_to_remove.append(coord)
	for coord in chunks_to_remove: unload_chunk(coord)
	
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var target_coord = center + Vector2i(x, z)
			if not active_chunks.has(target_coord) and not target_coord in generation_queue and not target_coord in generating_chunks:
				generation_queue.append(target_coord)
	
	if generation_queue.size() > 1:
		generation_queue.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())

func process_generation_queue():
	if is_generating or generation_queue.is_empty(): return
	is_generating = true
	var coord = generation_queue.pop_front()
	generating_chunks.append(coord) 
	
	await generate_single_chunk(coord)
	
	generating_chunks.erase(coord) 
	is_generating = false

func generate_single_chunk(coord: Vector2i):
	var map_data = {}
	var idx = 0
	for step in steps:
		await step.execute_step(map_data, CHUNK_SIZE, idx, coord)
		idx += 1
		
	# 初始化生成时，将数据存入总管字典
	chunk_block_data[coord] = map_data.duplicate(true) 
	render_chunk(coord, map_data)

# ========================================================
# 【核心机制】：数据名称兼容器
# ========================================================
func get_block_name_from_data(id_data) -> String:
	# 玩家放的方块是 String，生成器生成的是 Vector2i，这里统一解析
	if typeof(id_data) == TYPE_STRING:
		return id_data
	elif typeof(id_data) == TYPE_VECTOR2I:
		return steps[id_data.x].get_block_name_by_local_id(id_data.y)
	return "air"

# ========================================================
# 【核心机制】：破坏与放置
# ========================================================
func break_block_at(global_pos: Vector3) -> bool:
	var cx = floor(global_pos.x / CHUNK_SIZE.x)
	var cz = floor(global_pos.z / CHUNK_SIZE.z)
	var coord = Vector2i(cx, cz)
	
	if not chunk_block_data.has(coord): return false
	
	var map_data = chunk_block_data[coord]
	var local_pos = Vector3i(global_pos.round()) - Vector3i(coord.x * CHUNK_SIZE.x, 0, coord.y * CHUNK_SIZE.z)
	
	if map_data.has(local_pos):
		# 1. 消除数据
		map_data.erase(local_pos)
		chunk_block_data[coord] = map_data 
		
		# 2. 铲除旧区块
		if active_chunks.has(coord):
			var old_chunk = active_chunks[coord]
			if is_instance_valid(old_chunk):
				old_chunk.queue_free()
			active_chunks.erase(coord)
			
		# 3. 瞬间重绘
		render_chunk(coord, map_data)
		return true
	return false

func place_block_at(global_pos: Vector3, block_name: String) -> bool:
	var cx = floor(global_pos.x / CHUNK_SIZE.x)
	var cz = floor(global_pos.z / CHUNK_SIZE.z)
	var coord = Vector2i(cx, cz)
	
	if not chunk_block_data.has(coord): return false
	
	var map_data = chunk_block_data[coord]
	var local_pos = Vector3i(global_pos.round()) - Vector3i(coord.x * CHUNK_SIZE.x, 0, coord.y * CHUNK_SIZE.z)
	
	# 如果目标位置已经有非空气方块，拒绝放置 (防止重叠穿模)
	if map_data.has(local_pos):
		if get_block_name_from_data(map_data[local_pos]) != "air":
			return false
			
	# 将玩家选择的方块名字写入字典
	map_data[local_pos] = block_name
	chunk_block_data[coord] = map_data 
	
	if active_chunks.has(coord):
		var old_chunk = active_chunks[coord]
		if is_instance_valid(old_chunk):
			old_chunk.queue_free()
		active_chunks.erase(coord)
		
	# 瞬间重绘包含了新方块的区块
	render_chunk(coord, map_data)
	return true

# ========================================================
# 区块渲染器
# ========================================================
func render_chunk(coord: Vector2i, map_data: Dictionary):
	var chunk_root = Node3D.new()
	chunk_root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk_root.position = Vector3(coord.x * CHUNK_SIZE.x, 0, coord.y * CHUNK_SIZE.z)
	area_node.add_child(chunk_root)
	active_chunks[coord] = chunk_root
	
	var grouped_pos = {} 
	var all_solid_positions = [] 
	
	for pos in map_data.keys():
		if is_block_hidden_internal(pos, map_data): continue
		var name = get_block_name_from_data(map_data[pos])
		if name == "air": continue
		
		if not grouped_pos.has(name): grouped_pos[name] = []
		grouped_pos[name].append(Vector3(pos))
		all_solid_positions.append(Vector3(pos))
	
	for name in grouped_pos.keys():
		var positions = grouped_pos[name]
		create_multimesh(chunk_root, name, positions)
		
	if all_solid_positions.size() > 0:
		var body = StaticBody3D.new()
		body.name = "Chunk_Collision"
		var col_owner = CollisionShape3D.new()
		col_owner.shape = create_merged_chunk_collision_shape(all_solid_positions)
		body.add_child(col_owner)
		chunk_root.add_child(body)

func create_multimesh(parent, block_name, positions):
	var data = BlockDatabase.get_block_data(block_name)
	if not data: return
	
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://object/block.gdshader")
	mat.set_shader_parameter("texture_top", BlockDatabase.get_texture(data.get("top","")))
	mat.set_shader_parameter("texture_side", BlockDatabase.get_texture(data.get("side","")))
	mat.set_shader_parameter("texture_bottom", BlockDatabase.get_texture(data.get("bottom","")))
	mat.set_shader_parameter("emission_energy", data.get("brightness", 0.0))
	
	var mm = MultiMesh.new()
	mm.mesh = base_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = positions.size()
	for i in range(positions.size()):
		var t = Transform3D()
		t.origin = positions[i]
		mm.set_instance_transform(i, t)
		
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)

func create_merged_chunk_collision_shape(positions) -> ConcavePolygonShape3D:
	var total_vertices = positions.size() * 36
	var all_faces = PackedVector3Array()
	all_faces.resize(total_vertices)
	var idx = 0
	for pos in positions:
		for v in collision_cache_faces:
			all_faces[idx] = v + pos
			idx += 1
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(all_faces)
	return shape

func is_block_hidden_internal(pos: Vector3i, map_data: Dictionary) -> bool:
	var n = Vector3i(pos.x, pos.y+1, pos.z)
	if not map_data.has(n) or get_block_name_from_data(map_data[n]) == "air": return false
	n = Vector3i(pos.x, pos.y-1, pos.z)
	if not map_data.has(n) or get_block_name_from_data(map_data[n]) == "air": return false
	n = Vector3i(pos.x+1, pos.y, pos.z)
	if not map_data.has(n) or get_block_name_from_data(map_data[n]) == "air": return false
	n = Vector3i(pos.x-1, pos.y, pos.z)
	if not map_data.has(n) or get_block_name_from_data(map_data[n]) == "air": return false
	n = Vector3i(pos.x, pos.y, pos.z+1)
	if not map_data.has(n) or get_block_name_from_data(map_data[n]) == "air": return false
	n = Vector3i(pos.x, pos.y, pos.z-1)
	if not map_data.has(n) or get_block_name_from_data(map_data[n]) == "air": return false
	return true

func unload_chunk(coord: Vector2i):
	if active_chunks.has(coord):
		if is_instance_valid(active_chunks[coord]): active_chunks[coord].queue_free()
		active_chunks.erase(coord)
		chunk_block_data.erase(coord)

func start_preview_generation():
	clear_all_chunks()
	var diameter = render_distance * 2 + 1
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			generation_queue.append(Vector2i(x, z))
	generation_queue.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
	while not generation_queue.is_empty():
		if not generate_preview:
			clear_all_chunks()
			return
		await process_generation_queue()

func clear_all_chunks():
	if area_node:
		for child in area_node.get_children(): child.free()
	active_chunks.clear()
	chunk_block_data.clear()
	generation_queue.clear()
	generating_chunks.clear()
	is_generating = false
