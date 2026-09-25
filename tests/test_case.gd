class_name TestCase
extends Node
## Base for scene-based tests: PASS/FAIL checks, game-time waits, and an
## ErrorLog that fails the run on any engine or script error.
## Subclasses implement _run() and call finish() at the end.

## Game-time watchdog: a hung test (e.g. a level that failed to load) fails
## instead of looping forever.
@export var timeout_seconds := 1800.0

var _failures: Array[String] = []
var _log := ErrorLog.new()
var _finished := false


func _ready() -> void:
	OS.add_logger(_log)
	get_tree().create_timer(timeout_seconds).timeout.connect(_on_timeout)
	await _run()
	finish()


func _on_timeout() -> void:
	check(false, "test timed out after %.0fs of game time" % timeout_seconds)
	finish()


## Override with the test body. May await.
func _run() -> void:
	pass


func seconds(duration: float) -> Signal:
	return get_tree().create_timer(duration).timeout


func check(condition: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures.append(label)


func finish() -> void:
	if _finished:
		return
	_finished = true
	OS.remove_logger(_log)
	check(_log.errors.is_empty(), "no engine/script errors (%d)" % _log.errors.size())
	for error in _log.errors.slice(0, 10):
		print("    ", error)
	print("\n%d failure(s)" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
