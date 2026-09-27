extends "res://tests/support/test_case.gd"


func _parse_ok(text: String) -> Variant:
	var r := BnJson.parse(text)
	check(r.ok(), "parse failed: %s (line %d)" % [r.error, r.error_line])
	check_eq(r.warnings, PackedStringArray(), "warnings")
	return r.value


func test_scalars() -> void:
	check_eq(_parse_ok("[1, 1.0, -3, 0.5, 1000, true, false, null]"),
			[1, 1.0, -3, 0.5, 1000, true, false, null])


func test_int_float_round_trip() -> void:
	check_eq(BnJson.stringify(_parse_ok("[1000, 1000.0, -0.5, 0]")), "[1000,1000.0,-0.5,0]")


func test_key_order_preserved() -> void:
	var v: Dictionary = _parse_ok('{"type": "mapgen", "//": "note", "a": 1, "//2": "x"}')
	check_eq(v.keys(), ["type", "//", "a", "//2"])
	check_eq(BnJson.stringify(v), '{"type":"mapgen","//":"note","a":1,"//2":"x"}')


func test_nested_and_empty() -> void:
	check_eq(_parse_ok(' { "a" : [ [ ], { } , [1,[2]] ] } '), {"a": [[], {}, [1, [2]]]})


func test_strings_utf8_raw() -> void:
	var v: Array = _parse_ok('["é☃😀", "#.~│"]')
	check_eq(v, ["é☃😀", "#.~│"])
	check_eq(BnJson.stringify(v), '["é☃😀","#.~│"]')


func test_canonical_escapes() -> void:
	var text := '["q\\"b\\\\n\\nt\\tr\\rc\\u0001"]'
	var v: Array = _parse_ok(text)
	check_eq(v, ["q\"b\\n\nt\tr\rc" + char(1)])
	check_eq(BnJson.stringify(v), text.replace(" ", ""))


func test_unicode_escapes_decode_with_warning() -> void:
	var r := BnJson.parse('["\\u00e9\\ud83d\\ude00\\/"]')
	check(r.ok(), r.error)
	check_eq(r.value, ["é😀/"])
	check_eq(r.warnings.size(), 1, "non-canonical escape warning")


func test_float_format_matches_formatter() -> void:
	check_eq(BnJson.format_float(1000.0), "1000.0")
	check_eq(BnJson.format_float(1.5), "1.5")
	check_eq(BnJson.format_float(0.1234567), "0.123457")
	check_eq(BnJson.format_float(-0.0), "-0.0")
	check_eq(BnJson.format_float(1e-7), "0.0")
	check_eq(BnJson.format_float(0.00001), "0.00001")


func test_lossy_constructs_warn() -> void:
	for text in ['{"a": 1, "a": 2}', "[6e6]", "[18446744073709551615]", "﻿[1]"]:
		var r := BnJson.parse(text)
		check(r.ok(), "%s: %s" % [text, r.error])
		check_eq(r.warnings.size(), 1, "warnings for %s" % text)


func test_errors_report_line() -> void:
	var cases := {
		"": 1,
		"[1,": 1,
		'{"a" 1}': 1,
		"[1]\nx": 2,
		'[\n"unterminated': 2,
		"[\n\n tru]": 3,
		"[1.]": 1,
		"[-]": 1,
		'{"a":1,}': 1,
		'["\\x"]': 1,
	}
	for text: String in cases:
		var r := BnJson.parse(text)
		check(not r.ok(), "expected an error for %s" % text.c_escape())
		check_eq(r.error_line, cases[text], "error line for %s (%s)" % [text.c_escape(), r.error])


func test_stringify_string_names_and_nesting() -> void:
	check_eq(BnJson.stringify({&"k": [{"x": null}]}), '{"k":[{"x":null}]}')
