#!/usr/bin/env sh

set -e

# Set up path to the Savi compiler to use, based on the path provided via arg.
SAVI=$(CDPATH= cd -- "$(dirname -- "${1:-build/savi-debug}")" && pwd)/$(basename "${1:-build/savi-debug}")

# Change directory to the directory where this script is located.
cd -- "$(dirname -- "$0")"


# Start running integation tests.
echo "Running integration tests..."
echo
for subdir in $(find ./ -maxdepth 1 -mindepth 1 -type d | sort --ignore-case); do
  # If this subdirectory has an expected errors file, use that test approach.
  if [ -f "$subdir/savi.errors.txt" ]; then
    actual=$(cd $subdir && "$SAVI" --backtrace 2>&1 || true)
    expected=$(cat $subdir/savi.errors.txt)
    if [ "$actual" = "$expected" ]; then
      echo "✓    $subdir"
    else
      did_fail="X"
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
    fi

  # Otherwise, we have no test approaches left that can be tried.
  else
    did_fail="X"
    echo "FAIL $subdir"
    echo "     (missing files needed for integration testing)"
    echo "     (please add a savi.errors.txt file to that directory)"
  fi
  echo
done

# If any test failed, report overall failure here.
if [ -n "$did_fail" ]; then
  echo "INTEGRATION TESTS FAILED"
  exit 1
fi
