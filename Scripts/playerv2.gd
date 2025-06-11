extends CharacterBody3D

# player nodes

@onready var head: Node3D = $Head
@onready var standing_col: CollisionShape3D = $StandingCol
@onready var crouching_collision: CollisionShape3D = $CrouchingCollision
@onready var crouch_ray: RayCast3D = $crouch_ray
@onready var camera_3d: Camera3D = $Head/head_bobber/Camera3D
@onready var head_bobber: Node3D = $Head/head_bobber

# speed and movement variables

@export var current_speed := 5.0
const walking_speed := 5.0
const sprinting_speed := 10.0
const crouching_speed := 3.0
const JUMP_VELOCITY := 5
const mouse_sens := 0.25
var lerp_speed := 10.0
var air_lerp_speed := 3.0
var direction := Vector3.ZERO
var jumps := 2
# player states

var walking := false
var sprinting := false
var crouching := false
var sliding := false

# sliding variables

var slide_timer := 0.0
var slider_time_max := 1
var slide_vector := Vector2.ZERO
var slide_speed := 13.0

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

func _physics_process(delta: float) -> void:
	
	# movement input to use for sliding checking and for direction.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backwards")

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		jumps = 2

	# Jump
	if Input.is_action_just_pressed("jump") and jumps == 2:
		velocity.y = JUMP_VELOCITY
		jumps -= 1
		sliding = false
	elif Input.is_action_just_pressed("jump") and jumps == 1:
		jumps -= 1
		velocity.y = JUMP_VELOCITY * 1.2
		sliding = false
	#if Input.is_action_just_pressed("jump") and jumps == 2:
		#jumps -= 1
		#velocity.y = JUMP_VELOCITY
	#elif Input.is_action_just_pressed("jump") and jumps == 1:
		#jumps -= 1
		
	# Crouching and Sprinting (note crouching is dominant over sprinting)
	if Input.is_action_pressed("crouch") || sliding:
		
		current_speed = lerp(current_speed,crouching_speed, lerp_speed * delta)
		head.position.y = lerp(head.position.y, .3, lerp_speed * delta)
		
		standing_col.disabled = true
		crouching_collision.disabled = false
		
		# start sliding logic if sprinting in a direction while crouching
		if sprinting and input_dir != Vector2.ZERO:
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
		slide_timer -= delta
		camera_3d.rotation.z = lerp(camera_3d.rotation.z,-deg_to_rad(3.0), lerp_speed * delta)
		if slide_timer <= 0:
			sliding = false
	else:
		camera_3d.rotation.z = lerp(camera_3d.rotation.z,-deg_to_rad(0.0), lerp_speed * delta)
			
			
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
	if is_on_floor() && !sliding && input_dir != Vector2.ZERO:
		head_bobbing_vector.y = sin(head_bobbing_index)
		head_bobbing_vector.x = sin(head_bobbing_index/2)*0.5
		
		# aryan if you ever need to change the sway of the bob change the division!
		head_bobber.position.y = lerp(head_bobber.position.y, head_bobbing_vector.y * (head_bobbing_current_intensity/2), delta * lerp_speed)
		head_bobber.position.x = lerp(head_bobber.position.x, head_bobbing_vector.x * head_bobbing_current_intensity, delta * lerp_speed)
	else:
		head_bobber.position.y = lerp(head_bobber.position.y, 0.0, delta * lerp_speed)
		head_bobber.position.x = lerp(head_bobber.position.x, 0.0, delta * lerp_speed)
	
	# Directional Movement
	if is_on_floor():
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), lerp_speed * delta)
	else:
		if input_dir != Vector2.ZERO:
			direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), air_lerp_speed * delta)

	if sliding:
		direction = (transform.basis * Vector3(slide_vector.x,0, slide_vector.y)).normalized()
		current_speed = (slide_timer + 0.1) * slide_speed
		
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
