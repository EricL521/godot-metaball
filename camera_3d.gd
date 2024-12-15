extends Camera3D

@export var movement_speed: int = 1
@export var rotate_speed: int = 1

@onready var mouse_captured: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if mouse_captured:
		var movement_multiplier = movement_speed * delta
		if Input.is_action_pressed("move_fast"):
			movement_multiplier *= 2
		if Input.is_action_pressed("move_forward"):
			global_translate(-Vector3(global_transform.basis.z.x, 0, global_transform.basis.z.z).normalized() * movement_multiplier)
		if Input.is_action_pressed("move_back"):
			global_translate(Vector3(global_transform.basis.z.x, 0, global_transform.basis.z.z).normalized() * movement_multiplier)
		if Input.is_action_pressed("move_left"):
			global_translate(-Vector3(global_transform.basis.x.x, 0, global_transform.basis.x.z).normalized() * movement_multiplier)
		if Input.is_action_pressed("move_right"):
			global_translate(Vector3(global_transform.basis.x.x, 0, global_transform.basis.x.z).normalized() * movement_multiplier)
		if Input.is_action_pressed("move_up"):
			global_translate(-Vector3.UP * movement_multiplier)
		if Input.is_action_pressed("move_down"):
			global_translate(Vector3.UP * movement_multiplier)
	
func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		global_rotate(Vector3.UP, - event.relative.x * rotate_speed / 500)
		global_rotate(global_transform.basis.x, event.relative.y * rotate_speed / 500)
	if mouse_captured and event.is_action_pressed("escape"):
		mouse_captured = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif not mouse_captured and event.is_action_pressed("enter"):
		mouse_captured = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
