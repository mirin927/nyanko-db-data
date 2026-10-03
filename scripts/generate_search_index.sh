#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname "$script_dir")
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/nyanko-search.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
swiftc -O -module-cache-path "$build_dir/modules" \
    "$project_dir/NyankoDB/Models/NameSearch.swift" \
    "$script_dir/GenerateSearchIndex.swift" -o "$build_dir/generate"
"$build_dir/generate" "$project_dir" "$@"
