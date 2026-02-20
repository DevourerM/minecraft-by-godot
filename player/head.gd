extends Node3D

@export var mouse_sensitivity := 0.003
enum CameraMode { FIRST_PERSON, THIRD_PERSON_BACK, THIRD_PERSON_FRONT }
var current_cam_mode = CameraMode.FIRST_PERSON

@onready var camera_arm = $CameraArm3D
@onready var player = get_parent()
@onready var steve = $"../steve"

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_update_camera_visuals()

# 【关键修改】：从 _unhandled_input 改为 _input，强制接收鼠标，无视 UI 遮挡！
func _input(event):
	# 1. 鼠标锁定与释放
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# 2. 视角切换
	if event.is_action_pressed("toggle_camera"):
		current_cam_mode = (current_cam_mode + 1) % 3 as CameraMode
		_update_camera_visuals()

	# 3. 鼠标转头逻辑 + 打印输出测试
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# 左右转动玩家
		player.rotate_y(-event.relative.x * mouse_sensitivity)
		# 上下转动头部
		self.rotate_x(-event.relative.y * mouse_sensitivity)
		self.rotation.x = clamp(self.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		


func _update_camera_visuals():
	if not camera_arm or not steve: return
	match current_cam_mode:
		CameraMode.FIRST_PERSON:
			camera_arm.spring_length = 0.0
			camera_arm.rotation_degrees.y = 0
			steve.hide()
		CameraMode.THIRD_PERSON_BACK:
			camera_arm.spring_length = 4.0
			camera_arm.rotation_degrees.y = 0
			steve.show()
		CameraMode.THIRD_PERSON_FRONT:
			camera_arm.spring_length = 4.0
			camera_arm.rotation_degrees.y = 180
			steve.show()
