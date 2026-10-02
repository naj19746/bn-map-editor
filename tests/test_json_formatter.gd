extends "res://tests/support/test_case.gd"
## JsonFormatter against output from BN's json_formatter binary (the expected
## texts here were made with it). test_roundtrip checks every BN file.


func _formats(input: String, expected: String) -> void:
	var r := JsonFormatter.format(input)
	check(r.ok(), r.error)
	check_eq(r.text, expected)


func test_formats_compact_json() -> void:
	_formats('[{"type":"mapgen","weight":1000,"x":[1,2],"f":2.50}]',
			'[\n  {\n    "type": "mapgen",\n    "weight": 1000,\n    "x": [ 1, 2 ],\n    "f": 2.5\n  }\n]\n')


func test_already_formatted_is_unchanged() -> void:
	var text := '[\n  {\n    "x": [ 1, 2 ],\n    "o": { "a": "b" }\n  }\n]\n'
	_formats(text, text)


func test_rows_and_blueprint_wrap() -> void:
	# Even inside a collection that's kept on one line.
	_formats('[{"a":{"rows":["ab","cd"],"y":[1,2]}}]',
			'[\n  {\n    "a": { "rows": [\n        "ab",\n        "cd"\n      ], "y": [ 1, 2 ] }\n  }\n]\n')
	# One row stays on its line.
	_formats('[{"x":{"b":{"rows":["ab"]},"c":{"blueprint":["a","b"]}}}]',
			'[\n  {\n    "x": { "b": { "rows": [ "ab" ] }, "c": { "blueprint": [\n          "a",\n          "b"\n' \
			+ '        ] } }\n  }\n]\n')


func test_long_lines_wrap() -> void:
	var a := "a".repeat(54)
	var b := "b".repeat(69)
	_formats('[{"long":[["%s","%s"],[1,2]]}]' % [a, b],
			'[\n  {\n    "long": [\n      [\n        "%s",\n        "%s"\n      ],\n      [ 1, 2 ]\n    ]\n  }\n]\n' % [a, b])


func test_line_length_counts_bytes() -> void:
	# 58 characters, but 116 bytes: too long for one line.
	var e := "é".repeat(58)
	_formats('[{"w":["%s","x"]}]' % e, '[\n  {\n    "w": [\n      "%s",\n      "x"\n    ]\n  }\n]\n' % e)


func test_numbers_as_bn_writes_them() -> void:
	# Exponents on ints multiply by 100 per step in BN's reader.
	_formats('[{"n":[1e3,1e-3,1.5e2,.5,-0.0,0.1234567,-7,1.]}]',
			'[\n  {\n    "n": [ 1000000, 0, 150.0, 0.5, -0.0, 0.123457, -7, 1.0 ]\n  }\n]\n')


func test_strings_and_member_names() -> void:
	# Values keep their escapes; names are decoded and written back with
	# JsonOut's escapes. A trailing comma gets through.
	_formats('[{"\\u00e9\\/\\u0001":"\\u00e9\\/","q":[1,],}]',
			'[\n  {\n    "é/\\u0001": "\\u00e9\\/",\n    "q": [ 1 ]\n  }\n]\n')


func test_invalid_json_is_an_error() -> void:
	for bad: String in ["[1,", "", "[1 2]", "{\"a\" 1}", "{\"a\"::1}", "{1:2}", "[01]", "[+1]", "[,1]",
			"[\"a\\q\"]", "[\"a\\u12\"]", "[\"a\nb\"]", "[\"a\tb\"]", "[tru]", "[truex]", "[1] x",
			"{\"rows\":\"x\"}", "[\"abc", "﻿[1]"]:
		var r := JsonFormatter.format(bad)
		check(not r.ok(), "expected an error for %s" % JSON.stringify(bad))
		check_eq(r.text, "")
