extends Sprite2D

@export var updater: Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	updater.connect("gpu_sync", on_gpu_sync)

func on_gpu_sync(new_tex: ImageTexture):
	texture = new_tex
