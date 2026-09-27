class_name BnJson
extends RefCounted
## JSON reader/writer for BN data files.
##
## Godot's JSON class can't be used for saving: it turns every int into a float
## and writes 1000 back as 1000.0. This reader keeps int vs float and key order,
## and stringify() writes compact JSON that json_formatter lays out, so
## format(stringify(parse(f))) reproduces an already-formatted file byte-for-byte.
##
## Values are native types: Dictionary (insertion-ordered), Array, String, int,
## float, bool and null. Like json_formatter, a number is a float iff its text
## contains '.'. Constructs that parse but won't write back identically
## (non-canonical escapes, duplicate keys, exponents, ints beyond 64 bits, a BOM)
## are reported in ParseResult.warnings.


class ParseResult:
	var value: Variant = null
	## Empty on success.
	var error := ""
	## 1-based line of the error.
	var error_line := 0
	var warnings := PackedStringArray()
	## Byte offset each warning refers to, parallel to [member warnings].
	var warning_offsets := PackedInt64Array()
	## When the top-level value is an array: each element's [start, end) byte
	## range in the input, so an untouched element can be written back as it was.
	var spans: Array[Vector2i] = []

	func ok() -> bool:
		return error.is_empty()


static var _needs_escape: RegEx = RegEx.create_from_string("[\\x00-\\x1f\"\\\\]")


static func parse(text: String) -> ParseResult:
	return parse_bytes(text.to_utf8_buffer())


static func parse_bytes(bytes: PackedByteArray) -> ParseResult:
	return _Parser.new(bytes).run()


## Returns compact JSON, or "" (after push_error) if [param value] holds a type
## JSON can't represent.
static func stringify(value: Variant) -> String:
	var parts := PackedStringArray()
	if not _write(value, parts):
		return ""
	return "".join(parts)


static func _write(value: Variant, parts: PackedStringArray) -> bool:
	match typeof(value):
		TYPE_NIL:
			parts.append("null")
		TYPE_BOOL:
			parts.append("true" if value else "false")
		TYPE_INT:
			parts.append(str(value))
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				push_error("BnJson: can't write %s" % value)
				return false
			parts.append(format_float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			parts.append(encode_string(String(value)))
		TYPE_ARRAY:
			parts.append("[")
			var first := true
			for item: Variant in value:
				if not first:
					parts.append(",")
				first = false
				if not _write(item, parts):
					return false
			parts.append("]")
		TYPE_DICTIONARY:
			parts.append("{")
			var first := true
			for key: Variant in value:
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					push_error("BnJson: non-string key %s" % key)
					return false
				if not first:
					parts.append(",")
				first = false
				parts.append(encode_string(String(key)))
				parts.append(":")
				if not _write(value[key], parts):
					return false
			parts.append("}")
		_:
			push_error("BnJson: can't write a %s" % type_string(typeof(value)))
			return false
	return true


## Formats a float the way json_formatter does: std::to_string (six decimals),
## trailing zeros stripped, but always keeping one digit after the point.
static func format_float(x: float) -> String:
	var s := ("%.6f" % x).rstrip("0")
	if s.ends_with("."):
		s += "0"
	return s


## Quotes a string with the minimal escapes. Non-ASCII is written raw.
static func encode_string(s: String) -> String:
	if _needs_escape.search(s) == null:
		return "\"" + s + "\""
	var parts := PackedStringArray(["\""])
	for i in s.length():
		var c := s.unicode_at(i)
		match c:
			0x22: parts.append("\\\"")
			0x5c: parts.append("\\\\")
			0x0a: parts.append("\\n")
			0x09: parts.append("\\t")
			0x0d: parts.append("\\r")
			0x08: parts.append("\\b")
			0x0c: parts.append("\\f")
			_:
				if c < 0x20:
					parts.append("\\u%04x" % c)
				else:
					parts.append(char(c))
	parts.append("\"")
	return "".join(parts)


class _Parser:
	const QUOTE := 0x22
	const BACKSLASH := 0x5c

	var b: PackedByteArray
	var n: int
	var pos := 0
	var result := ParseResult.new()

	func _init(bytes: PackedByteArray) -> void:
		b = bytes
		n = bytes.size()

	func run() -> ParseResult:
		if n >= 3 and b[0] == 0xef and b[1] == 0xbb and b[2] == 0xbf:
			pos = 3
			_warn("UTF-8 byte order mark")
		_skip_ws()
		var value: Variant = _array(true) if pos < n and b[pos] == 0x5b else _value()
		if result.ok():
			_skip_ws()
			if pos < n:
				_fail("trailing data after the top-level value")
		if result.ok():
			result.value = value
		return result

	func _fail(msg: String) -> void:
		if result.ok():
			result.error = msg
			result.error_line = b.slice(0, mini(pos, n)).count(0x0a) + 1

	func _warn(msg: String) -> void:
		result.warnings.append("line %d: %s" % [b.slice(0, mini(pos, n)).count(0x0a) + 1, msg])
		result.warning_offsets.append(pos)

	func _skip_ws() -> void:
		while pos < n:
			var c := b[pos]
			if c == 0x20 or c == 0x0a or c == 0x0d or c == 0x09:
				pos += 1
			else:
				return

	func _value() -> Variant:
		_skip_ws()
		if pos >= n:
			_fail("unexpected end of input")
			return null
		var c := b[pos]
		if c == 0x7b:
			return _object()
		if c == 0x5b:
			return _array()
		if c == QUOTE:
			return _string()
		if c == 0x2d or (c >= 0x30 and c <= 0x39):
			return _number()
		if _literal("true"):
			return true
		if _literal("false"):
			return false
		if _literal("null"):
			return null
		_fail("unexpected character '%s'" % char(c))
		return null

	func _literal(word: String) -> bool:
		var end := pos + word.length()
		if end <= n and b.slice(pos, end).get_string_from_ascii() == word:
			pos = end
			return true
		return false

	func _object() -> Variant:
		pos += 1
		var d := {}
		_skip_ws()
		if pos < n and b[pos] == 0x7d:
			pos += 1
			return d
		while true:
			_skip_ws()
			if pos >= n or b[pos] != QUOTE:
				_fail("expected a member name")
				return null
			var key: Variant = _string()
			if not result.ok():
				return null
			_skip_ws()
			if pos >= n or b[pos] != 0x3a:
				_fail("expected ':' after member name")
				return null
			pos += 1
			var v: Variant = _value()
			if not result.ok():
				return null
			if d.has(key):
				_warn("duplicate key \"%s\"" % key)
			d[key] = v
			_skip_ws()
			if pos < n and b[pos] == 0x2c:
				pos += 1
			elif pos < n and b[pos] == 0x7d:
				pos += 1
				return d
			else:
				_fail("expected ',' or '}'")
				return null
		return null

	## With [param top], records each element's span in result.spans.
	func _array(top := false) -> Variant:
		pos += 1
		var a := []
		_skip_ws()
		if pos < n and b[pos] == 0x5d:
			pos += 1
			return a
		while true:
			_skip_ws()
			var start := pos
			var v: Variant = _value()
			if not result.ok():
				return null
			if top:
				result.spans.append(Vector2i(start, pos))
			a.append(v)
			_skip_ws()
			if pos < n and b[pos] == 0x2c:
				pos += 1
			elif pos < n and b[pos] == 0x5d:
				pos += 1
				return a
			else:
				_fail("expected ',' or ']'")
				return null
		return null

	func _string() -> Variant:
		var open := pos
		var start := pos + 1
		var close := b.find(QUOTE, start)
		var esc := b.find(BACKSLASH, start)
		if close < 0:
			_fail("unterminated string")
			return null
		if esc < 0 or esc > close:
			pos = close + 1
			return b.slice(start, close).get_string_from_utf8()
		# Slow path: decode escapes segment by segment.
		var parts := PackedStringArray()
		var seg := start
		while true:
			close = b.find(QUOTE, seg)
			esc = b.find(BACKSLASH, seg)
			if close < 0:
				pos = n
				_fail("unterminated string")
				return null
			if esc < 0 or esc > close:
				parts.append(b.slice(seg, close).get_string_from_utf8())
				pos = close + 1
				break
			parts.append(b.slice(seg, esc).get_string_from_utf8())
			pos = esc
			if esc + 1 >= n:
				_fail("unterminated string")
				return null
			var e := b[esc + 1]
			seg = esc + 2
			match e:
				0x22: parts.append("\"")
				0x5c: parts.append("\\")
				0x2f: parts.append("/")
				0x62: parts.append(char(0x08))
				0x66: parts.append(char(0x0c))
				0x6e: parts.append("\n")
				0x72: parts.append("\r")
				0x74: parts.append("\t")
				0x75:
					var cp := _hex4(esc + 2)
					if cp < 0:
						return null
					seg = esc + 6
					if cp >= 0xd800 and cp <= 0xdbff and seg + 1 < n \
							and b[seg] == BACKSLASH and b[seg + 1] == 0x75:
						var lo := _hex4(seg + 2)
						if lo < 0:
							return null
						if lo >= 0xdc00 and lo <= 0xdfff:
							cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00)
							seg += 6
					parts.append(char(cp))
				_:
					_fail("invalid escape '\\%s'" % char(e))
					return null
		var s := "".join(parts)
		if BnJson.encode_string(s) != b.slice(open, pos).get_string_from_utf8():
			_warn("non-canonical escape in string \"%s\"" % s.c_escape())
		return s

	func _hex4(at: int) -> int:
		if at + 4 > n:
			_fail("truncated \\u escape")
			return -1
		var hex := b.slice(at, at + 4).get_string_from_ascii()
		if not hex.is_valid_hex_number():
			_fail("invalid \\u escape")
			return -1
		return hex.hex_to_int()

	func _number() -> Variant:
		var start := pos
		if b[pos] == 0x2d:
			pos += 1
		var digits_start := pos
		if not _digits():
			return null
		var is_float := false
		var has_exp := false
		if pos < n and b[pos] == 0x2e:
			is_float = true
			pos += 1
			if not _digits():
				return null
		if pos < n and (b[pos] == 0x65 or b[pos] == 0x45):
			has_exp = true
			pos += 1
			if pos < n and (b[pos] == 0x2b or b[pos] == 0x2d):
				pos += 1
			if not _digits():
				return null
		var text := b.slice(start, pos).get_string_from_ascii()
		if has_exp:
			# json_formatter mangles exponents; this becomes a plain float.
			_warn("exponent in number %s" % text)
			return text.to_float()
		if is_float:
			return text.to_float()
		if pos - digits_start > 18:
			var big := text.to_float()
			if absf(big) >= 9.2e18:
				_warn("integer %s doesn't fit in 64 bits" % text)
				return big
		return text.to_int()

	## Consumes one or more digits.
	func _digits() -> bool:
		var start := pos
		while pos < n and b[pos] >= 0x30 and b[pos] <= 0x39:
			pos += 1
		if pos == start:
			_fail("invalid number")
			return false
		return true
