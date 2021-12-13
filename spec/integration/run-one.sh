#!/usr/bin/env sh

set -e

# The first arg is the subdir name to test.
subdir="$1"

# Set up path to the Savi compiler to use, based on the path provided via arg.
SAVI=$(CDPATH= cd -- "$(dirname -- "${2:-build/savi-debug}")" && pwd)/$(basename "${2:-build/savi-debug}")

# Change directory to the directory where this script is located.
cd -- "$(dirname -- "$0")"

# Confirm that a subdirectory was actually given.
if [ -z $subdir ]; then
  echo "FAIL (no subdirectory name given)"
  exit 2
fi

# Confirm that the given subdirectory name exists.
if ! [ -d $subdir ]; then
  echo "FAIL $subdir"
  echo "     (does not exist within $(pwd))"
  exit 2
fi

# If this subdirectory has an expected errors file, use that testing strategy.
if [ -f "$subdir/savi.errors.txt" ]; then
  actual=$(cd $subdir && "$SAVI" --backtrace 2>&1 || true)
  expected=$(cat $subdir/savi.errors.txt)
  if [ "$actual" = "$expected" ]; then
    echo "✓    $subdir"
  else
    echo "---"
    echo "---"
    echo
    echo "FAIL $subdir"
    echo
    echo "---"
    echo
    echo "EXPECTED $expected"
    echo
    echo "---"
    echo
    echo "ACTUAL $actual"
    echo
    echo "---"
    echo "---"
    exit 1
  fi

## NOTE: When adding new testing strategy, also add a description to the
##       integration testing documentation in `spec/integration/README.md`

# Otherwise, we have no test approaches left that can be tried.
else
  echo "FAIL $subdir"
  echo "     (missing files needed for integration testing)"
  echo "     (please add a savi.errors.txt file to that directory)"
  exit 2
fi
echo
