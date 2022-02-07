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

# Test that the output of running the compiler matches the expected errors.
test_error_output() {
  actual=$(cd $subdir && "$SAVI" --backtrace 2>&1 || true)
  expected=$(cat $subdir/savi.errors.txt)
  if [ "$actual" != "$expected" ]; then
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
    return 1
  fi
}

# Test that the content of the given files matches the expected "after" content.
test_fixed_files_content() {
  for filename in $(find "$subdir/savi.fix.after.dir" | cut -d/ -f 3-); do
    actual=$(cat "$subdir/$filename")
    expected=$(cat "$subdir/savi.fix.after.dir/$filename")
    if [ "$actual" != "$expected" ]; then
      echo "---"
      echo "---"
      echo
      echo "FAIL $subdir"
      echo
      echo "---"
      echo
      echo "EXPECTED $filename:"
      echo "$expected"
      echo
      echo "---"
      echo
      echo "ACTUAL $filename:"
      echo "$actual"
      echo
      echo "---"
      echo "---"
      return 1
    fi
  done
}

# Test that the output of running the compiler matches the expected errors.
test_run_output() {
  actual=$(env SAVI="$SAVI" sh -c "cd $subdir && ./savi.run.test.sh")
  expected=$(cat $subdir/savi.run.output.txt)
  if [ "$actual" != "$expected" ]; then
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
    return 1
  fi
}

# If this subdirectory has auto-fix information, use that testing strategy.
if [ -d "$subdir/savi.fix.before.dir" ] \
&& [ -d "$subdir/savi.fix.after.dir" ] \
&& [ -f "$subdir/savi.errors.txt" ]; then
  cp -r "$subdir/savi.fix.before.dir/"* $subdir/
  cleanup_files=$(ls "$subdir/savi.fix.before.dir/"* | cut -d/ -f -1,3-)

  if ! test_error_output; then
    rm -rf ${cleanup_files}
    exit 1
  fi

  if ! "$SAVI" --cd "$subdir" --backtrace --fix; then
    echo "FAIL $subdir"
    echo "     (savi command failed to execute)"
    rm -rf ${cleanup_files}
    exit 1
  fi

  if ! test_fixed_files_content; then
    rm -rf ${cleanup_files}
    exit 1
  fi

  rm -rf ${cleanup_files}

# If this subdirectory has an expected errors file, use that testing strategy.
elif [ -f "$subdir/savi.errors.txt" ]; then
  test_error_output

# If this subdirectory has a script and expected output file, use that strategy.
elif [ -f "$subdir/savi.run.test.sh" ] \
  && [ -f "$subdir/savi.run.output.txt" ]; then
  test_run_output

## NOTE: When adding new testing strategy, also add a description to the
##       integration testing documentation in `spec/integration/README.md`

# Otherwise, we have no test approaches left that can be tried.
else
  echo "FAIL $subdir"
  echo "     (missing files needed for integration testing)"
  echo "     (see spec/integration/README.md for more info)"
  exit 2
fi

echo "✓    $subdir"
echo
