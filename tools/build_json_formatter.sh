#!/usr/bin/env bash
# Builds BN's json_formatter (tools/format/format.cpp + src/json.cpp) into build/.
# Usage: tools/build_json_formatter.sh [BN_PATH]
# BN_PATH defaults to $BN_PATH, then ../Cataclysm-BN. The compiler is $CXX,
# else clang++, else g++.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bn="${1:-${BN_PATH:-$root/../Cataclysm-BN}}"

for f in tools/format/format.cpp src/json.cpp; do
    if [[ ! -f "$bn/$f" ]]; then
        echo "error: $bn/$f not found; pass the BN checkout path" >&2
        exit 1
    fi
done

cxx="${CXX:-}"
if [[ -z "$cxx" ]]; then
    if command -v clang++ >/dev/null; then
        cxx=clang++
    elif command -v g++ >/dev/null; then
        cxx=g++
    else
        echo "error: no C++ compiler found (install clang++ or g++, or set CXX)" >&2
        exit 1
    fi
fi

out="$root/build/json_formatter"
case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) out+=".exe" ;;
esac

mkdir -p "$root/build"
echo "Building $out with $cxx from $bn"
"$cxx" -std=c++23 -O2 -DCATA_IN_TOOL -I"$bn/src" \
    "$bn/tools/format/format.cpp" "$bn/src/json.cpp" -o "$out"
