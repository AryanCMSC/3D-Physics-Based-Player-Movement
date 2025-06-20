extends CharacterBody3D

# player nodes

@onready var head: Node3D = $Head
@onready var standing_col: CollisionShape3D = $StandingCol
@onready var crouching_collision: CollisionShape3D = $CrouchingCollision
@onready var crouch_ray: RayCast3D = $crouch_ray
@onready var camera_3d: Camera3D = $Head/wall_run_cam/head_bobber/Camera3D
@onready var head_bobber: Node3D = $Head/wall_run_cam/head_bobber
@onready var player_v2: CharacterBody3D = $"."
@onready var wall_run_cam: Node3D = $Head/wall_run_cam
@onready var wall_check_ray_highR: RayCast3D = $WallCheckRayHighR
@onready var wall_check_ray_lowR: RayCast3D = $WallCheckRayLowR
@onready var wall_check_ray_highL: RayCast3D = $WallCheckRayHighL
@onready var wall_check_ray_lowL: RayCast3D = $WallCheckRayLowL

# speed and movement variables

@export var current_speed := 6.0
const walking_speed := 6.0
const sprinting_speed := 11.0
const crouching_speed := 3.0
const JUMP_VELOCITY := 5
const dashing_speed := 30
@export var mouse_sens := 0.25
const lerp_speed := 10.0
const air_lerp_speed := 3.0
const fov_lerp_speed := 8.0
var direction := Vector3.ZERO
@export var jumps := 2
@export var FOV := 70
const FOV_CHANGE := 2
# player states

var walking := false
var sprinting := false
var crouching := false
var sliding := false
var dashing := false
var can_dash := true
var can_wallrun := false
var wallrunning := false
var wallrun_jump := false


# wallrun

var wallrun_delay := 0.2
@onready var wallrun_delay_default := wallrun_delay
var wallrun_angle := 15
var wallrun_current_angle := 0
var side := ""
var wall_jump_horizontal := 1.5
var wall_jump_vertical := 0.75
var wall_jump_factor := 0.4
var wall_jump_dir := Vector3.ZERO
# stairs

const MAX_STEP_HEIGHT := 0.5
var _snapped_to_stairs_last_frame := false
var _last_frame_was_on_floor := -INF


# sliding variables

var slide_timer := 0.0
var slider_time_max := 1.0
var slide_vector := Vector2.ZERO
var slide_speed := 12.0
var slope_acceleration := 3.0  
var max_slope_speed := 30.0   
var current_slide_speed := 12.0
var uphill_deceleration := 10.0 
var min_slide_speed := 1.0 
# headbobbing variables

const head_bobbing_sprinting_speed := 22
const head_bobbing_walking_speed := 14
const head_bobbing_crouching_speed := 10

const head_bobbing_crouching_intensity := 0.05
const head_bobbing_sprinting_intensity := 0.2
const head_bobbing_walking_intensity := 0.1

var head_bobbing_vector := Vector2.ZERO
var head_bobbing_index := 0.0
var head_bobbing_current_intensity := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _input(event: InputEvent) -> void:
	
	# mouse capturing/exiting
	if event.is_action_pressed("left_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  
	if event.is_action_pressed("esc"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# player head movement
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sens))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# checking for slope when sliding
	
func is_on_slope() -> bool:
	if not is_on_floor():
		return false
	var floor_normal := get_floor_normal()
	var slope_angle := floor_normal.angle_to(Vector3.UP)
	
	return slope_angle > deg_to_rad(17)
	
func is_moving_uphill() -> bool:
	if not is_on_slope():
		return false
	
	var floor_normal := get_floor_normal()
	var movement_direction := Vector3(velocity.x, 0, velocity.z).normalized()
	
	# Get the uphill direction (opposite to the downhill slope)
	var downhill_direction := Vector3(floor_normal.x, 0, floor_normal.z).normalized()
	var uphill_direction := -downhill_direction
	
	# Check if movement direction aligns with uphill direction
	var dot_product := movement_direction.dot(uphill_direction)
	
	# If dot product > 0.5, we're moving more uphill than not (~60 degree threshold)
	return dot_product > 0.5
	# walking on stairs

func is_surface_too_steep(normal : Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > player_v2.floor_max_angle
	
func _snap_down_to_stairs_check() -> void:
	var did_snap := false
	var floor_below : bool = %stairs_below_ray.is_colliding() and not is_surface_too_steep(%stairs_below_ray.get_collision_normal())
	var was_on_floor_last_frame := Engine.get_physics_frames() - _last_frame_was_on_floor == 1
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result := PhysicsTestMotionResult3D.new()
		if _run_body_test_motion(player_v2.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			var translate_y := body_test_result.get_travel().y
			player_v2.position.y += translate_y
			apply_floor_snap()
			did_snap = true
	_snapped_to_stairs_last_frame = did_snap
	
func _snap_up_stairs_check(delta: float) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame: return false
	# Don't snap stairs if trying to jump, also no need to check for stairs ahead if not moving
	if player_v2.velocity.y > 0 or (player_v2.velocity * Vector3(1,0,1)).length() == 0: return false
	var expected_move_motion : Vector3 = player_v2.velocity * Vector3(1,0,1) * delta
	var step_pos_with_clearance := player_v2.global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	# Run a body_test_motion slightly above the pos we expect to move to, towards the floor.
	#  We give some clearance above to ensure there's ample room for the player.
	#  If it hits a step <= MAX_STEP_HEIGHT, we can teleport the player on top of the step
	#  along with their intended motion forward.
	var down_check_result := KinematicCollision3D.new()
	if (player_v2.test_move(step_pos_with_clearance, Vector3(0,-MAX_STEP_HEIGHT*2,0), down_check_result)
	and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D"))):
		var step_height := ((step_pos_with_clearance.origin + down_check_result.get_travel()) - player_v2.global_position).y
		# Note I put the step_height <= 0.01 in just because I noticed it prevented some physics glitchiness
		# 0.02 was found with trial and error. Too much and sometimes get stuck on a stair. Too little and can jitter if running into a ceiling.
		# The normal character controller (both jolt & default) seems to be able to handled steps up of 0.1 anyway
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_check_result.get_position() - player_v2.global_position).y > MAX_STEP_HEIGHT: return false
		%stairs_ahead_ray.global_position = down_check_result.get_position() + Vector3(0,MAX_STEP_HEIGHT,0) + expected_move_motion.normalized() * 0.1
		%stairs_ahead_ray.force_raycast_update()
		if %stairs_ahead_ray.is_colliding() and not is_surface_too_steep(%stairs_ahead_ray.get_collision_normal()):
			player_v2.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			return true
	return false

func _run_body_test_motion(from : Transform3D, motion : Vector3,  result : PhysicsTestMotionResult3D = null) -> bool:
		if not result : result = PhysicsTestMotionResult3D.new()
		var params := PhysicsTestMotionParameters3D.new()
		params.from = from
		params.motion = motion
		return PhysicsServer3D.body_test_motion(player_v2.get_rid(), params, result)
		
		
# wallrunning
func process_wallrun() -> void:
	if can_wallrun:
		if is_on_wall() and ((wall_check_ray_lowR.is_colliding() and wall_check_ray_highR.is_colliding()) or (wall_check_ray_highL.is_colliding() and wall_check_ray_lowL.is_colliding())) and Input.is_action_pressed("move_forward") and Input.is_action_pressed("sprint"):
			dashing = false
			crouching = false
			var collision := get_slide_collision(0)
			var normal := collision.get_normal()
			
			var wallrun_dir := Vector3.UP.cross(normal)
			var player_view_dir := -camera_3d.global_transform.basis.z
			var dot := wallrun_dir.dot(player_view_dir)
			if dot < 0:
				wallrun_dir = -wallrun_dir
				
			var wallrun_axis_2d := Vector2(wallrun_dir.x, wallrun_dir.z)
			var view_dir_2d := Vector2(player_view_dir.x, player_view_dir.z)
			var angle := wallrun_axis_2d.angle_to(view_dir_2d)
			
			angle = rad_to_deg(angle)
			
			if dot < 0:
				angle = -angle
				
			if angle > 85:
				wallrunning = false
				return
				
			wallrun_dir += -normal * 0.01
			
			wallrunning = true
			
			side = get_side(collision.get_position())
			
			velocity.y = -0.01
			direction = wallrun_dir
		
		else:
			wallrunning = false
			
			
			
func process_wallrun_rotation(delta: float) -> void:
		if wallrunning:
			if side == "RIGHT":
				wallrun_current_angle += delta * 60
				wallrun_current_angle = clamp(wallrun_current_angle, -wallrun_angle, wallrun_angle)
			elif side == "LEFT":
				wallrun_current_angle -= delta * 60
				wallrun_current_angle = clamp(wallrun_current_angle, -wallrun_angle, wallrun_angle)
			
		else:
			if wallrun_current_angle > 0:
				wallrun_current_angle -= delta * 40
				wallrun_current_angle = max(0, wallrun_current_angle)
			elif wallrun_current_angle < 0:
				wallrun_current_angle += delta * 40
				wallrun_current_angle = min(wallrun_current_angle, 0)
		
		wall_run_cam.rotation_degrees = Vector3(0,0,1) * wallrun_current_angle

func get_side(point: Vector3) -> String:
	point = to_local(point)
	
	if point.x > 0:
		return "RIGHT"
	elif point.x < 0:
		return "LEFT"
	else: return "CENTER"
	
func _physics_process(delta: float) -> void:
	
	# movement input to use for sliding checking and for direction.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
		wallrun_delay = clamp(wallrun_delay - delta, 0, wallrun_delay_default)
		if wallrun_delay == 0:
			can_wallrun = true
		
	else:
		jumps = 2
		_last_frame_was_on_floor = Engine.get_physics_frames()
		can_wallrun = false
		wallrunning = false
		wallrun_jump = false
		wallrun_delay = wallrun_delay_default
	
	process_wallrun()
	process_wallrun_rotation(delta)
	
		
	# dashing 
		
	if Input.is_action_just_pressed("dash") and can_dash:
		
		dashing = true
		can_dash = false
		
		var dash_duration := 0.2
		await get_tree().create_timer(dash_duration).timeout
		
		dashing = false
		
		var dash_cooldown := 2.0
		
		await get_tree().create_timer(dash_cooldown).timeout
		
		can_dash = true
	
	# Jump
	if Input.is_action_just_pressed("jump") and jumps == 2:
		velocity.y = JUMP_VELOCITY
		jumps -= 1
		sliding = false
	elif Input.is_action_just_pressed("jump") and jumps == 1:
		jumps -= 1
		velocity.y = JUMP_VELOCITY * 1.2
		sliding = false
		
	# jumping while wallrunning
	
	if Input.is_action_just_pressed("jump") and wallrunning:
		can_wallrun = false
		wallrunning = false
		dashing = false
		jumps += 1
		velocity = Vector3.ZERO
		
		velocity.y = JUMP_VELOCITY * wall_jump_vertical
		wallrun_jump = true

		if side == "LEFT":
			wall_jump_dir = global_transform.basis.x * wall_jump_horizontal
		elif side == "RIGHT":
			wall_jump_dir = -global_transform.basis.x * wall_jump_horizontal
		
		wall_jump_dir *= wall_jump_factor
	
		direction = (direction * (1 - wall_jump_factor)) + wall_jump_dir
		get_tree().create_timer(0.2).timeout.connect(func() -> void: wallrun_jump = false)

	
	
	# Crouching and Sprinting (note crouching is dominant over sprinting)
	if (Input.is_action_pressed("crouch") || sliding) and not wallrunning:
		
		current_speed = lerp(current_speed,crouching_speed, lerp_speed * delta)
		head.position.y = lerp(head.position.y, .3, lerp_speed * delta)
		
		standing_col.disabled = true
		crouching_collision.disabled = false
		crouching = true
		
		# start sliding logic if sprinting in a direction while crouching
		if sprinting and input_dir != Vector2.ZERO and is_on_floor():
			sliding = true
			slide_vector = input_dir
			slide_timer = slider_time_max
			
		crouching = true
		walking = false
		sprinting = false
		
	# walking and sprinting logic
		
	elif !crouch_ray.is_colliding():
		head.position.y = lerp(head.position.y, .8, lerp_speed * delta)
		standing_col.disabled = false
		crouching_collision.disabled = true
		if Input.is_action_pressed("sprint"):
			crouching = false
			walking = false
			sprinting = true
			current_speed = lerp(current_speed,sprinting_speed, delta * lerp_speed)
			
		else:
			sprinting = false
			walking = true
			crouching = false
			current_speed = lerp(current_speed,walking_speed, delta * lerp_speed)
			
	# handling sliding time ending
	
	if sliding:
	# Only decrement timer when NOT on a slope
		if not is_on_slope():
			slide_timer -= delta
			# Reset slide speed to normal when back on flat ground
			current_slide_speed = lerp(current_slide_speed, slide_speed, delta * lerp_speed)
			
		elif is_moving_uphill():
			current_slide_speed = max(current_slide_speed - (uphill_deceleration * delta), min_slide_speed)
		
			# Stop sliding if speed gets too low
			if current_slide_speed <= min_slide_speed:
				sliding = false
				current_slide_speed = slide_speed
			else:
				# Timer counts down normally when going uphill
				slide_timer -= delta
		else:
			# Accelerate while on slope
			current_slide_speed = min(current_slide_speed + (slope_acceleration * delta), max_slope_speed)
		
		camera_3d.rotation.z = lerp(camera_3d.rotation.z,-deg_to_rad(3.0), lerp_speed * delta)
		if slide_timer <= 0:
			sliding = false
			current_slide_speed = slide_speed  # Reset to default when slide ends
	else:
		camera_3d.rotation.z = lerp(camera_3d.rotation.z,-deg_to_rad(0.0), lerp_speed * delta)
		current_slide_speed = slide_speed  # Reset to default when not sliding
			
			
	# headbob
	if sprinting:
		head_bobbing_current_intensity = head_bobbing_sprinting_intensity
		head_bobbing_index += head_bobbing_sprinting_speed * delta
	elif walking:
		head_bobbing_current_intensity = head_bobbing_walking_intensity
		head_bobbing_index += head_bobbing_walking_speed * delta
	elif crouching:
		head_bobbing_current_intensity = head_bobbing_crouching_intensity
		head_bobbing_index += head_bobbing_crouching_speed * delta
		
	# headbob checking and logic
	if (is_on_floor() or _snapped_to_stairs_last_frame) && !sliding && input_dir != Vector2.ZERO:
		head_bobbing_vector.y = sin(head_bobbing_index)
		head_bobbing_vector.x = sin(head_bobbing_index/2)*0.5
		
		# aryan if you ever need to change the sway of the bob change the division!
		head_bobber.position.y = lerp(head_bobber.position.y, head_bobbing_vector.y * (head_bobbing_current_intensity/2), delta * lerp_speed)
		head_bobber.position.x = lerp(head_bobber.position.x, head_bobbing_vector.x * head_bobbing_current_intensity, delta * lerp_speed)
	else:
		head_bobber.position.y = lerp(head_bobber.position.y, 0.0, delta * lerp_speed)
		head_bobber.position.x = lerp(head_bobber.position.x, 0.0, delta * lerp_speed)
		
	# fov
	
	var velocity_clamped : float = clamp(velocity.length(), walking_speed, dashing_speed * 4)
	var target_fov := FOV + FOV_CHANGE * velocity_clamped
	camera_3d.fov = lerp(camera_3d.fov, target_fov, fov_lerp_speed * delta)
	
	
	# Directional Movement
	if is_on_floor() or _snapped_to_stairs_last_frame:
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), lerp_speed * delta)
	else:
		if input_dir != Vector2.ZERO:
			direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), air_lerp_speed * delta)

	if sliding:
		direction = (transform.basis * Vector3(slide_vector.x,0, slide_vector.y)).normalized()
		current_speed = current_slide_speed
		
	if dashing:
		direction = -player_v2.transform.basis.z.normalized()
		current_speed = dashing_speed
		velocity = current_speed * direction
		
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		
	if not _snap_up_stairs_check(delta):
		move_and_slide()
		_snap_down_to_stairs_check()
		
