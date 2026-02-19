extends Node
var player: Player
var _last_w_press: float = 0.0

func enter(_player: Player):
	player = _player

func physics_update(delta):
	# 重力与跳跃
	if not player.is_on_floor():
		player.velocity.y -= player.gravity * delta
	elif Input.is_action_just_pressed("jump") and not Input.is_action_pressed("sneak"):
		player.velocity.y = player.jump_velocity

	# 【双击W 疾跑检测】
	if Input.is_action_just_pressed("move_forward") and not Input.is_action_pressed("sneak"):
		var time_now = Time.get_ticks_msec() / 1000.0
		if time_now - _last_w_press < 0.3:
			get_parent().change_state($"../Sprint")
			return
		_last_w_press = time_now

	# 获取移动输入 (使用你的映射名)
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.length() == 0:
		get_parent().change_state($"../Idle")
		return

	# 【潜行 (Shift) 检测】
	var is_sneaking = Input.is_action_pressed("sneak")
	var current_speed = player.sneak_speed if is_sneaking else player.walk_speed

	# 移动执行
	var direction = (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	player.velocity.x = direction.x * current_speed
	player.velocity.z = direction.z * current_speed
	player.move_and_slide()
	
	# 摆动四肢：潜行时摆动变慢 (0.6倍)
	player.animate_limbs(delta, 0.6 if is_sneaking else 1.0)
