$SAVI
file=$(mktemp)
sh -c "echo foo; echo bar" > $file; bin/example < $file
