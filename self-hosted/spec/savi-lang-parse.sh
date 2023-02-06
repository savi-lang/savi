#!/usr/bin/env sh

# Go to the right working directory and set up shell options
cd -- "$(dirname -- "$0")"
set -e

find savi-lang-parse -name '*.savi' | xargs -I '{}' \
  sh -c 'cat {} | ../bin/savi-lang-parse > {}.ast.yaml'

git diff --exit-code savi-lang-parse
