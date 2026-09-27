extends "res://tests/support/test_case.gd"


func _formatter() -> JsonFormatter:
	var f := JsonFormatter.new()
	if not f.is_available():
		skip("json_formatter not built (tools/build_json_formatter.sh)")
		return null
	return f


func test_formats_compact_json() -> void:
	var f := _formatter()
	if f == null:
		return
	var r := f.format('[{"type":"mapgen","weight":1000,"x":[1,2],"f":2.50}]')
	check(r.ok(), r.error)
	check_eq(r.text, '[\n  {\n    "type": "mapgen",\n    "weight": 1000,\n    "x": [ 1, 2 ],\n    "f": 2.5\n  }\n]\n')


func test_already_formatted_is_unchanged() -> void:
	var f := _formatter()
	if f == null:
		return
	var text := '[\n  {\n    "x": [ 1, 2 ],\n    "o": { "a": "b" }\n  }\n]\n'
	check_eq(f.format(text).text, text)


func test_invalid_json_is_an_error() -> void:
	var f := _formatter()
	if f == null:
		return
	var r := f.format("[1,")
	check(not r.ok(), "expected an error")
	check_eq(r.text, "")


func test_missing_executable_is_an_error() -> void:
	var r := JsonFormatter.new("/nonexistent/json_formatter").format("[]")
	check(r.error.contains("not found"), r.error)
