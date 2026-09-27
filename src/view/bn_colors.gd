class_name BnColors
extends RefCounted
## BN color names ("light_gray", "i_red", "h_white", "c_yellow_green", ...) as
## foreground and background RGB, following src/color.cpp.
##
## BN draws through curses color pairs over 8 base colors, where "bold" makes
## the foreground bright and "blink" makes the background bright. The RGB
## values are BN's defaults from data/raw/colors.json.
##   c_<fg>        fg on black ("c_" may be left out)
##   c_<fg>_<bg>   fg on bg, bg one of red, white, green, yellow, magenta, cyan
##   h_<fg>        fg on blue (highlighted)
##   i_<fg>        black on fg (inverted)
## The few pairs BN defines oddly (c_black_red is bold, c_dark_gray_red isn't)
## are taken at face value by name.

const BLACK := Color8(0, 0, 0)
const RED := Color8(255, 0, 0)
const GREEN := Color8(0, 110, 0)
const BROWN := Color8(97, 56, 28)
const BLUE := Color8(10, 10, 220)
const MAGENTA := Color8(139, 58, 98)
const CYAN := Color8(0, 150, 180)
const GRAY := Color8(150, 150, 150)
const DGRAY := Color8(99, 99, 99)
const LRED := Color8(255, 150, 150)
const LGREEN := Color8(0, 255, 0)
const YELLOW := Color8(255, 255, 0)
const LBLUE := Color8(100, 100, 255)
const LMAGENTA := Color8(254, 0, 254)
const LCYAN := Color8(0, 240, 255)
const WHITE := Color8(255, 255, 255)

## Foreground color names.
const FG := {
	"black": BLACK, "white": WHITE, "light_gray": GRAY, "dark_gray": DGRAY,
	"red": RED, "light_red": LRED, "green": GREEN, "light_green": LGREEN,
	"blue": BLUE, "light_blue": LBLUE, "cyan": CYAN, "light_cyan": LCYAN,
	"magenta": MAGENTA, "pink": LMAGENTA, "brown": BROWN, "yellow": YELLOW,
}

## Background names in "c_<fg>_<bg>". Curses backgrounds are the dim colors:
## "white" is light gray and "yellow" is brown.
const BG := {
	"red": RED, "white": GRAY, "green": GREEN, "yellow": BROWN, "magenta": MAGENTA,
	"cyan": CYAN,
}


## A fg/bg pair. [member known] is false when BN wouldn't recognise the name
## (it then draws c_unset, white on black; bgcolor falls back to i_white).
class Pair:
	var fg := WHITE
	var bg := BLACK
	var known := true

	func _init(p_fg := WHITE, p_bg := BLACK, p_known := true) -> void:
		fg = p_fg
		bg = p_bg
		known = p_known


static var _cache := {}


## Parses a "color" value (color_from_string).
static func parse(name: String) -> Pair:
	var cached: Pair = _cache.get(name)
	if cached:
		return cached
	var p := _parse(_normalize(name))
	_cache[name] = p
	return p


## Parses a "bgcolor" value: the name of the background, drawn as i_<name>.
static func parse_bg(name: String) -> Pair:
	var p := parse("i_" + name)
	return p if p.known else Pair.new(BLACK, WHITE, false)


static func _normalize(name: String) -> String:
	var n := name
	if n.substr(1, 1) != "_":
		n = "c_" + n
	# The deprecated "ltred"/"dkgray" spellings ("light_"/"dark_" contain
	# neither "lt" nor "dk").
	return n.replace("lt", "light_").replace("dk", "dark_")


static func _parse(n: String) -> Pair:
	var prefix := n.substr(0, 2)
	var rest := n.substr(2)
	match prefix:
		"h_":
			if FG.has(rest):
				return Pair.new(FG[rest], BLUE)
		"i_":
			if FG.has(rest):
				return Pair.new(BLACK, FG[rest])
		"c_":
			if FG.has(rest):
				return Pair.new(FG[rest], BLACK)
			var cut := rest.rfind("_")
			if cut > 0 and FG.has(rest.substr(0, cut)) and BG.has(rest.substr(cut + 1)):
				return Pair.new(FG[rest.substr(0, cut)], BG[rest.substr(cut + 1)])
	return Pair.new(WHITE, BLACK, false)
