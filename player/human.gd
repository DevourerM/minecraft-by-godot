class_name Player
extends CharacterBody3D

@onready var steve = $steve
@onready var arm_l = $steve.find_child("*rm_L", true, false)
@onready var arm_r = $steve.find_child("*rm_R", true, false)
@onready var leg_l = $steve.find_child("*eg_L", true, false)
@onready var leg_r = $steve.find_child("*eg_R", true, false)

@export var walk_speed := 5.0
@export var fly_speed := 10.0
@export var jump_velocity := 5.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_flying := false
var _last_jump_time := 0.0
var _anim_timer := 0.0

# --- 新增：挥手动作计时器 ---
var _action_timer := 0.0
const ACTION_DURATION := 0.15 # 挥一次手需要 0.15 秒

func _physics_process(delta):
	if is_flying:
		_handle_flying(delta)
	else:
		_handle_walking(delta)

	move_and_slide()
	
	# 【动作覆盖逻辑】：如果有攻击动作正在进行，强行覆盖右手的旋转！
	if _action_timer > 0:
		_action_timer -= delta
		if arm_r:
			# 使用 sin 曲线模拟挥起再落下的动作，最大角度约为 -60度 (-1.0 弧度)
			var progress = _action_timer / ACTION_DURATION
			var swing_angle = sin(progress * PI) * -1.0 
			arm_r.rotation.x = swing_angle

func _handle_walking(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump"):
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - _last_jump_time < 0.3:
			is_flying = true
			velocity.y = 0 
		elif is_on_floor():
			velocity.y = jump_velocity
		_last_jump_time = current_time

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * walk_speed
		velocity.z = direction.z * walk_speed
		if _action_timer <= 0: animate_limbs(delta) # 没攻击时正常走路摆手
	else:
		velocity.x = move_toward(velocity.x, 0, walk_speed)
		velocity.z = move_toward(velocity.z, 0, walk_speed)
		if _action_timer <= 0: reset_limbs(delta)

func _handle_flying(delta):
	if Input.is_action_just_pressed("jump"):
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - _last_jump_time < 0.3:
			is_flying = false
		_last_jump_time = current_time

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * fly_speed
		velocity.z = direction.z * fly_speed
		if _action_timer <= 0: animate_limbs(delta)
	else:
		velocity.x = move_toward(velocity.x, 0, fly_speed)
		velocity.z = move_toward(velocity.z, 0, fly_speed)
		if _action_timer <= 0: reset_limbs(delta)

	var vertical_dir = 0.0
	if Input.is_action_pressed("jump"): vertical_dir += 1.0
	velocity.y = move_toward(velocity.y, vertical_dir * fly_speed, fly_speed * 10 * delta)

# --- 鼠标点击：触发挥击 ---
func _input(event):
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("attack"):
			_action_timer = ACTION_DURATION # 重置动画时间，开始挥击
		elif event.is_action_pressed("interact"):
			_action_timer = ACTION_DURATION # 右键也挥击

# 正常走路/飞行的手脚摆动
func animate_limbs(delta: float):
	_anim_timer += delta * 12.0
	var swing = sin(_anim_timer) * 0.6
	if arm_l and arm_r and leg_l and leg_r:
		arm_l.rotation.x = swing
		arm_r.rotation.x = -swing # 右手走路也摆动
		leg_l.rotation.x = -swing
		leg_r.rotation.x = swing

func reset_limbs(delta: float):
	_anim_timer = 0.0
	if arm_l and arm_r and leg_l and leg_r:
		arm_l.rotation.x = lerp(arm_l.rotation.x, 0.0, delta * 15.0)
		arm_r.rotation.x = lerp(arm_r.rotation.x, 0.0, delta * 15.0)
		leg_l.rotation.x = lerp(leg_l.rotation.x, 0.0, delta * 15.0)
		leg_r.rotation.x = lerp(leg_r.rotation.x, 0.0, delta * 15.0)
