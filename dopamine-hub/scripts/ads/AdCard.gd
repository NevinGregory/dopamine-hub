extends Control


func _ready() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.2, 0.2, 1.0)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	
	# "AD" label
	var label := Label.new()
	label.text = "AD"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 72)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.anchors_preset = Control.PRESET_FULL_RECT
	add_child(label)