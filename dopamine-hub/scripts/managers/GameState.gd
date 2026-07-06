extends Node

# Persists per-game high scores to disk. Games call get_high_score(key) and
# report_score(key, value) -> returns true if it's a new best.

const SAVE_PATH: String = "user://gamestate.save"

var _high_scores: Dictionary = {}


func _ready() -> void:
	_load()


func get_high_score(key: String) -> int:
	return int(_high_scores.get(key, 0))


# Returns true if `value` beats the stored high score for `key`.
func report_score(key: String, value: int) -> bool:
	var prev: int = get_high_score(key)
	if value > prev:
		_high_scores[key] = value
		_save()
		return true
	return false


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed:
			_high_scores[k] = int(parsed[k])


func _save() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_high_scores))
	f.close()
