extends RefCounted
## Base class for tests. tests/run_tests.gd runs every method named test_*.
##
## Checks record failures instead of stopping the test, so one run reports
## everything that went wrong.

var failures := PackedStringArray()
var skip_reason := ""


func check(condition: bool, msg := "check failed") -> bool:
	if not condition:
		failures.append(msg)
	return condition


## Strict equality: 1 and 1.0 differ, and containers compare element-wise and
## in key order.
func check_eq(actual: Variant, expected: Variant, msg := "") -> bool:
	if same(actual, expected):
		return true
	failures.append("%sexpected %s, got %s" % [
		msg + ": " if msg else "", _show(expected), _show(actual)])
	return false


func skip(reason: String) -> void:
	skip_reason = reason


static func same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same(a[i], b[i]):
				return false
		return true
	if a is Dictionary:
		if a.keys() != b.keys():
			return false
		for k: Variant in a:
			if not same(a[k], b[k]):
				return false
		return true
	return a == b


static func _show(v: Variant) -> String:
	return "%s(%s)" % [type_string(typeof(v)), var_to_str(v)]
