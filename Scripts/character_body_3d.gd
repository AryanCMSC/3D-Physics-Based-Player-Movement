extends CharacterBody3D

#movement
@export_group("Movement")
@export var movement_speed := 8.0
@export var acceleration := 20.0
const JUMP_VELOCITY = 12
var jumps := 2
var gravity := -30.0
var is_third_person := false
# camera
@export_group("Camera Settings")
@export_range(0.0,1.0) var mouse_sens := 0.25


var _camera_input_direction := Vector2.ZERO
var last_movement_direction := Vector3.BACK
@onready var camera_pivot: Node3D = %"Camera Pivot"
@onready var camera: Camera3D = %Camera
@onready var spring_arm_3d: SpringArm3D = %SpringArm3D


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("left_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  
	if event.is_action_pressed("esc"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# perspective changer
	if event.is_action_pressed("perspective"):
		is_third_person = !is_third_person
		if is_third_person:
			spring_arm_3d.spring_length = 7.0
		else:
			spring_arm_3d.spring_length = 0.0	
	
		
func _unhandled_input(event: InputEvent) -> void:
	var is_camera_motion := (
		event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)
	if is_camera_motion:
		_camera_input_direction = event.screen_relative * mouse_sens
		

func _physics_process(delta: float) -> void:
	
	camera_pivot.rotation.x += _camera_input_direction.y * delta
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI / 6.0, PI / 3.0)
	camera_pivot.rotation.y -= _camera_input_direction.x * delta
	_camera_input_direction = Vector2.ZERO
	
	#movement code
	var raw_input := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	var forward := camera.global_basis.z
	var right := camera.global_basis.x
	var move_direction := forward * raw_input.y + right * raw_input.x
	move_direction.y = 0.0
	move_direction = move_direction.normalized()
	
	var vert_velocity := velocity.y
	velocity.y = 0.0
	velocity = velocity.move_toward(move_direction * movement_speed, acceleration * delta)
	
	# Add the gravity.
	if not is_on_floor(): 
		velocity.y = vert_velocity + gravity * delta
	else: jumps = 2
		
	
	# Handle jump.
	if Input.is_action_just_pressed("jump") and jumps == 2:
		jumps -= 1
		velocity.y = JUMP_VELOCITY
	elif Input.is_action_just_pressed("jump") and jumps == 1:
		jumps -= 1
		velocity.y = JUMP_VELOCITY * 1.2
		
	# Sprinting!!!
	
	if Input.is_action_pressed("sprint"):
		movement_speed = 10
	else:
		movement_speed = 5
		

	move_and_slide()
 
	if move_direction.length() > 0.2:
		last_movement_direction = move_direction
	var _target_angle := Vector3.BACK.signed_angle_to(last_movement_direction, Vector3.UP)
