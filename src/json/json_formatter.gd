class_name JsonFormatter
extends RefCounted
## BN's json_formatter (tools/format/format.cpp in a BN checkout), ported so
## the editor needs no native binary. format() gives the bytes the tool would
## write, and errors where its JsonIn would throw.
##
## The layout rules: the top level and its children always wrap. Deeper arrays
## and objects go on one line when that line (counted in UTF-8 bytes from
## before the separator in front of it, up to 120) fits, else they wrap.
## A "rows" or "blueprint" array with more than one element always wraps.
## String values keep their text as written (escapes included); member names
## are decoded and re-escaped. Numbers are read and written back the way the
## tool does, quirks included (see _number()).


class Result:
	var text := ""
	## Empty on success.
	var error := ""

	func ok() -> bool:
		return error.is_empty()


## Longest line, in bytes, that a nested array or object is kept on.
const MAX_LINE := 120

const _QUOTE := 0x22
const _BACKSLASH := 0x5c
const _MAX_INT := 9223372036854775807
## A string escape's character, for the escapes that aren't \u.
const _ESCAPES := {0x5c: 0x5c, 0x22: 0x22, 0x2f: 0x2f, 0x62: 0x08, 0x66: 0x0c,
		0x6e: 0x0a, 0x72: 0x0d, 0x74: 0x09}


static func format(json_text: String) -> Result:
	var result := Result.new()
	if json_text.is_empty():
		result.error = "json_formatter: input empty"
		return result
	var w := _Writer.new(json_text.to_utf8_buffer())
	w.value(-1, false)
	if w.error.is_empty():
		w.put("\n")
		result.text = "".join(w.parts)
	else:
		result.error = "json_formatter: %s (byte %d)" % [w.error, w.error_pos]
	return result


## One run: JsonIn's reading and JsonOut's writing, over a byte buffer.
class _Writer:
	var b: PackedByteArray
	var n: int
	var pos := 0
	## JsonIn::ate_separator: a ',' (or ':') was read since the last value.
	var ate_separator := false

	var parts := PackedStringArray()
	## Bytes written so far (JsonOut::tell()).
	var out_len := 0
	var need_separator := false
	var indent_level := 0
	var need_wrap: Array[bool] = []

	## While a collection is being tried on one line: the out_len it must not
	## pass. Anything inside it that wraps or runs long passes it too, so one
	## limit (the outermost try's) decides; -1 when not trying.
	var limit := -1
	var over := false

	var error := ""
	var error_pos := 0

	func _init(bytes: PackedByteArray) -> void:
		b = bytes
		n = b.size()

	func failed() -> bool:
		return over or not error.is_empty()

	func fail(msg: String) -> void:
		if error.is_empty():
			error = msg
			error_pos = pos

	# --- output (JsonOut) ---

	func put(s: String, bytes := -1) -> void:
		parts.append(s)
		out_len += s.length() if bytes < 0 else bytes
		if limit >= 0 and out_len > limit:
			over = true

	func indent() -> String:
		return " ".repeat(indent_level * 2)

	func write_separator() -> void:
		if not need_separator:
			return
		if indent_level < 2 or need_wrap.back():
			put(",\n" + indent())
		else:
			put(", ")
		need_separator = false

	func start(bracket: String, wrap: bool) -> void:
		write_separator()
		need_wrap.append(wrap)
		indent_level += 1
		if indent_level < 2 or wrap:
			put(bracket + "\n" + indent())
		else:
			put(bracket + " ")
		need_separator = false

	func end(bracket: String) -> void:
		indent_level -= 1
		if indent_level < 1 or need_wrap.back():
			put("\n" + indent() + bracket)
		else:
			put(" " + bracket)
		need_wrap.pop_back()
		need_separator = true

	## A scalar's text, after the separator it needs.
	func write_raw(s: String, bytes := -1) -> void:
		write_separator()
		put(s, bytes)
		need_separator = true

	# --- input (JsonIn) ---

	func peek() -> int:
		return b[pos] if pos < n else -1

	func eat_whitespace() -> void:
		while pos < n:
			var c := b[pos]
			if c != 0x20 and c != 0x0a and c != 0x09 and c != 0x0d:
				return
			pos += 1

	## JsonIn::end_value(): after a value, a ',' or the end of its container.
	func end_value() -> void:
		ate_separator = false
		eat_whitespace()
		var c := peek()
		if c == 0x2c:
			pos += 1
			ate_separator = true
		elif c == 0x5d or c == 0x7d or c == 0x3a or c == -1:
			pass
		else:
			fail("missing comma")

	## At a '[' / '{' (after whitespace): steps in.
	func open() -> void:
		pos += 1
		ate_separator = false

	## JsonIn::end_array()/end_object(): true (and steps out) at [param close].
	func at_close(close: int) -> bool:
		eat_whitespace()
		if peek() != close:
			if pos >= n:
				fail("couldn't find end of %s, reached EOF" % ("array" if close == 0x5d else "object"))
			return false
		# A trailing comma ("[1,]") gets through: JsonIn only checks for one
		# right after a ':'.
		pos += 1
		end_value()
		return true

	## Reads a string at pos (a '"'), validating it the way JsonIn does. Returns
	## its decoded bytes when [param decode], else an empty array; -1 in
	## string_end on error. The position after the closing quote is string_end.
	var string_end := 0

	func read_string(decode: bool) -> PackedByteArray:
		var out := PackedByteArray()
		var i := pos + 1
		while true:
			if i >= n:
				pos = i
				fail("couldn't find end of string, reached EOF")
				return out
			var c := b[i]
			if c == _QUOTE:
				break
			if c == _BACKSLASH:
				if i + 1 >= n:
					pos = i
					fail("couldn't find end of string, reached EOF")
					return out
				var e := b[i + 1]
				if _ESCAPES.has(e):
					if decode:
						out.append(_ESCAPES[e])
					i += 2
					continue
				if e != 0x75:
					pos = i
					fail("invalid escape sequence")
					return out
				var u := 0
				for k in 4:
					var h := b[i + 2 + k] if i + 2 + k < n else -1
					var d := -1
					if h >= 0x30 and h <= 0x39:
						d = h - 0x30
					elif h >= 0x61 and h <= 0x66:
						d = h - 0x61 + 10
					elif h >= 0x41 and h <= 0x46:
						d = h - 0x41 + 10
					if d < 0:
						pos = i
						fail("expected hex digit")
						return out
					u = (u << 4) | d
				if decode:
					out.append_array(_utf8(u))
				i += 6
				continue
			if c == 0x0d or c == 0x0a:
				pos = i
				fail("reached end of line without closing string")
				return out
			if c < 0x20:
				pos = i
				fail("invalid character inside string")
				return out
			if decode:
				out.append(c)
			i += 1
		string_end = i + 1
		return out

	## BN's utf16_to_utf8 (a lone surrogate is encoded as is).
	static func _utf8(u: int) -> PackedByteArray:
		if u < 0x80:
			return PackedByteArray([u])
		if u < 0x800:
			return PackedByteArray([0xc0 | (u >> 6), 0x80 | (u & 0x3f)])
		return PackedByteArray([0xe0 | (u >> 12), 0x80 | ((u >> 6) & 0x3f), 0x80 | (u & 0x3f)])

	## JsonOut::write(std::string): a member name's escapes.
	static func _escape(s: PackedByteArray) -> PackedByteArray:
		var out := PackedByteArray([_QUOTE])
		for c in s:
			match c:
				0x22: out.append_array("\\\"".to_ascii_buffer())
				0x5c: out.append_array("\\\\".to_ascii_buffer())
				0x08: out.append_array("\\b".to_ascii_buffer())
				0x0c: out.append_array("\\f".to_ascii_buffer())
				0x0a: out.append_array("\\n".to_ascii_buffer())
				0x0d: out.append_array("\\r".to_ascii_buffer())
				0x09: out.append_array("\\t".to_ascii_buffer())
				_:
					if c < 0x20:
						out.append_array(("\\u00%02X" % c).to_ascii_buffer())
					else:
						out.append(c)
		out.append(_QUOTE)
		return out

	# --- format.cpp ---

	func value(depth: int, force_wrap: bool) -> void:
		depth += 1
		eat_whitespace()
		var c := peek()
		if c == 0x5b or c == 0x7b:
			collection(depth, c == 0x7b, force_wrap)
		elif c == _QUOTE:
			var start_pos := pos
			read_string(false)
			if not error.is_empty():
				return
			write_raw(b.slice(start_pos, string_end).get_string_from_utf8(), string_end - start_pos)
			pos = string_end
			end_value()
		elif c == 0x2d or c == 0x2b or c == 0x2e or (c >= 0x30 and c <= 0x39):
			number()
		elif c == 0x74 or c == 0x66:
			var word := "true" if c == 0x74 else "false"
			if not literal(word):
				fail("not a boolean")
				return
			write_raw(word)
		elif c == 0x6e:
			if not literal("null"):
				fail("expected \"null\"")
				return
			write_raw("null")
		elif c == -1:
			fail("unexpected end of input")
		else:
			fail("expected JSON value but got '%c'" % c)

	func literal(word: String) -> bool:
		if pos + word.length() > n or b.slice(pos, pos + word.length()).get_string_from_ascii() != word:
			return false
		pos += word.length()
		end_value()
		return true

	## format_collection(): one line when it fits (depth > 1 only), else wrapped.
	func collection(depth: int, is_object: bool, force_wrap: bool) -> void:
		if depth > 1 and not force_wrap:
			if limit >= 0:
				# Inside another one-line try: if this doesn't fit on one line,
				# that one doesn't either.
				write_collection(depth, is_object, false)
				return
			var in_pos := pos
			var in_ate := ate_separator
			var out_parts := parts.size()
			var out_start := out_len
			var out_sep := need_separator
			var out_indent := indent_level
			var out_wrap := need_wrap.size()
			limit = out_start + MAX_LINE
			write_collection(depth, is_object, false)
			limit = -1
			if not error.is_empty():
				return
			if not over:
				return
			over = false
			pos = in_pos
			ate_separator = in_ate
			parts.resize(out_parts)
			out_len = out_start
			need_separator = out_sep
			indent_level = out_indent
			need_wrap.resize(out_wrap)
		write_collection(depth, is_object, true)

	func write_collection(depth: int, is_object: bool, wrap: bool) -> void:
		var close := 0x7d if is_object else 0x5d
		start("{" if is_object else "[", wrap)
		open()
		while not at_close(close):
			if failed():
				return
			if not is_object:
				value(depth, false)
				continue
			# A member: its name (re-escaped), then its value.
			eat_whitespace()
			if peek() != _QUOTE:
				fail("expected string but got '%c'" % peek() if pos < n else "reached EOF")
				return
			var name := read_string(true)
			if not error.is_empty():
				return
			pos = string_end
			end_value()
			eat_whitespace()
			if peek() != 0x3a:
				fail("expected pair separator ':'")
				return
			if ate_separator:
				fail("duplicate pair separator ':' not allowed")
				return
			pos += 1
			ate_separator = true
			var escaped := _escape(name)
			write_raw(escaped.get_string_from_utf8(), escaped.size())
			put(": ")
			need_separator = false
			var name_text := name.get_string_from_utf8()
			value(depth, (name_text == "rows" or name_text == "blueprint") and array_size() > 1)
			if failed():
				return
		if failed():
			return
		end("}" if is_object else "]")

	## How many elements the array at pos has; it must be an array (BN's
	## JsonArray throws otherwise). The input position is left as it was.
	func array_size() -> int:
		eat_whitespace()
		if peek() != 0x5b:
			fail("tried to start array, but found '%c', not '['" % peek())
			return 0
		var save_pos := pos
		var save_ate := ate_separator
		open()
		var count := 0
		while not at_close(0x5d):
			if not error.is_empty():
				return 0
			skip_value()
			if not error.is_empty():
				return 0
			count += 1
		pos = save_pos
		ate_separator = save_ate
		return count

	func skip_value() -> void:
		eat_whitespace()
		var c := peek()
		if c == _QUOTE:
			read_string(false)
			if error.is_empty():
				pos = string_end
				end_value()
		elif c == 0x5b or c == 0x7b:
			var close := c + 2
			open()
			while not at_close(close):
				if not error.is_empty():
					return
				if c == 0x7b:
					skip_value()
					if not error.is_empty():
						return
					eat_whitespace()
					if peek() != 0x3a:
						fail("expected pair separator ':'")
						return
					pos += 1
					ate_separator = true
				skip_value()
				if not error.is_empty():
					return
		elif c == 0x2d or (c >= 0x30 and c <= 0x39):
			while pos < n and _is_number_char(b[pos]):
				pos += 1
			end_value()
		elif c == 0x74:
			if not literal("true"):
				fail("expected \"true\"")
		elif c == 0x66:
			if not literal("false"):
				fail("expected \"false\"")
		elif c == 0x6e:
			if not literal("null"):
				fail("expected \"null\"")
		else:
			fail("expected JSON value but got '%c'" % c if c >= 0 else "unexpected end of input")

	static func _is_number_char(c: int) -> bool:
		return (c >= 0x30 and c <= 0x39) or c == 0x2b or c == 0x2d or c == 0x2e or c == 0x65 or c == 0x45

	## format.cpp's number branch: an int (get_uint64/get_int64, whose
	## exponent handling multiplies by 100 per positive step) unless the text
	## has a '.', then get_float() through std::to_string. Ints beyond int64
	## are an error here (the tool would write ones up to 2^64 - 1).
	func number() -> void:
		var start_pos := pos
		var end_pos := pos
		while end_pos < n and _is_number_char(b[end_pos]):
			end_pos += 1
		var is_float := b.slice(start_pos, end_pos).has(0x2e)
		var parsed := any_number()
		if not error.is_empty():
			return
		var negative: bool = parsed[0]
		var integral: int = parsed[1]
		var fract: int = parsed[2]
		var integral_exp: int = parsed[3]
		var fract_exp: int = parsed[4]
		if is_float:
			var sum := float(fract) * pow(10.0, fract_exp) + float(integral) * pow(10.0, integral_exp)
			write_raw(BnJson.format_float(-sum if negative else sum))
			return
		# JsonIn::get_any_int(), overflow checks and all.
		while fract_exp < 0:
			fract /= 10
			fract_exp += 1
		while fract_exp > 0:
			if fract > _MAX_INT / 10:
				fail("number too large")
				return
			fract *= 10
			fract_exp -= 1
		while integral_exp < 0:
			integral /= 10
			integral_exp += 1
		while integral_exp > 0:
			if integral > _MAX_INT / 100:
				fail("number too large")
				return
			integral *= 100
			integral_exp -= 1
		if integral > _MAX_INT - fract:
			fail("number too large")
			return
		integral += fract
		write_raw(str(-integral if negative else integral))

	## JsonIn::get_any_number(): [negative, integral, fract, integral_exp,
	## fract_exp]. Digits beyond int64 fail rather than wrap.
	func any_number() -> Array:
		var negative := false
		var integral := 0
		var fract := 0
		var integral_exp := 0
		var mod_e := 0
		var c := peek()
		pos += 1
		negative = c == 0x2d
		if negative:
			if pos >= n:
				fail("unexpected end of input")
				return []
			c = b[pos]
			pos += 1
		elif c != 0x2e and (c < 0x30 or c > 0x39):
			fail("expecting number but found '%c'" % c)
			return []
		if c == 0x30:
			c = b[pos] if pos < n else -1
			pos += 1
			if c >= 0x30 and c <= 0x39:
				fail("leading zeros not allowed")
				return []
		while c >= 0x30 and c <= 0x39:
			if integral > (_MAX_INT - 9) / 10:
				fail("number too large")
				return []
			integral = integral * 10 + (c - 0x30)
			c = b[pos] if pos < n else -1
			pos += 1
		if c == 0x2e:
			c = b[pos] if pos < n else -1
			pos += 1
			while c >= 0x30 and c <= 0x39:
				if fract > (_MAX_INT - 9) / 10:
					fail("number too large")
					return []
				fract = fract * 10 + (c - 0x30)
				mod_e -= 1
				c = b[pos] if pos < n else -1
				pos += 1
		if c == 0x65 or c == 0x45:
			c = b[pos] if pos < n else -1
			pos += 1
			if c == -1:
				fail("unexpected end of input")
				return []
			var neg := c == 0x2d
			if neg or c == 0x2b:
				c = b[pos] if pos < n else -1
				pos += 1
				if c == -1:
					fail("unexpected end of input")
					return []
			while c >= 0x30 and c <= 0x39:
				integral_exp = integral_exp * 10 + (c - 0x30)
				c = b[pos] if pos < n else -1
				pos += 1
			if neg:
				integral_exp = -integral_exp
		# Unget the character after the number.
		if c != -1:
			pos -= 1
		pos = mini(pos, n)
		end_value()
		return [negative, integral, fract, integral_exp, integral_exp + mod_e]
