#!/bin/sh

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_ROOT="$(dirname "$SCRIPT_PATH")"

CRYSTAL_LIB=$SCRIPT_ROOT/../lib/crystal_lib/src/main.cr
OUTPUT=$SCRIPT_ROOT/../src/lib_fswatch.cr

crystal run $CRYSTAL_LIB -- "$SCRIPT_ROOT/lib_fswatch.cr" |
  sed -e '/lib LibFSWatch/a\'$'\n''\ \ alias Bool = LibC::Int' |
  sed 's/LibC::Bool/Bool/g' |
  sed -e '/^.*enum EventFlag.*/i\'$'\n''\ \ @[Flags]' |
  sed '/$ALL_EVENT_FLAGS/ s/^/#/' > $OUTPUT

crystal tool format $OUTPUT

# libfswatch uses LibC::Bool that is not in std-lib
# $ALL_EVENT_FLAGS is not a valid symbol
