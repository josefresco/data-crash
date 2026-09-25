class_name ErrorLog
extends Logger
## Collects engine and script errors during a test run so tests fail on them,
## not just on their own checks. Warnings are ignored.
## Usage: var log := ErrorLog.new(); OS.add_logger(log) ... log.errors

var errors: PackedStringArray = []
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := rationale if not rationale.is_empty() else code
	# Engine shutdown noise from quitting mid-frame; not our bug.
	if text.begins_with("BUG: Unreferenced static string"):
		return
	_mutex.lock()
	errors.append("%s  (%s:%d %s)" % [text, file.get_file(), line, function])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
