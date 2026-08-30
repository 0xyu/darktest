extends SceneTree
func _init() -> void:
	var path := "res://resources/enemies/enemy_registry.tres"
	var uid := ResourceUID.path_to_uid(path)
	print("path_to_uid result: ", uid)
	print("has_id: ", ResourceUID.has_id(ResourceUID.text_to_id(uid)))
	print("has_id_for_file_uid: ", ResourceUID.has_id(ResourceUID.text_to_id("uid://n2oynqns6qvy")))
	quit()
