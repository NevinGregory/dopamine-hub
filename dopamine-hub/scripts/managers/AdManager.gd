extends Node


var games_played: int = 0


func on_game_finished() -> void:
	games_played += 1
	
	if games_played % 5 == 0:
		show_interstitial()


func show_interstitial() -> void:
	print("Interstitial ad shown")
	get_tree().paused = true
	
	# Auto-close after 2 seconds to simulate ad completion
	var close_timer := Timer.new()
	close_timer.one_shot = true
	close_timer.timeout.connect(_on_ad_closed)
	add_child(close_timer)
	close_timer.start(2.0)


func _on_ad_closed() -> void:
	print("Interstitial ad closed")
	get_tree().paused = false
