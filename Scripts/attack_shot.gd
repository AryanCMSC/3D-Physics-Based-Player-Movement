extends Node3D

const SPEED = 40.0

@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	position += transform.basis * Vector3(0,0, -SPEED) * delta
	if ray_cast_3d.is_colliding():
		mesh_instance_3d.visible = false
		queue_free()


func _on_timer_timeout() -> void:
	queue_free()
