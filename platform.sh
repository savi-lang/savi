#!/usr/bin/env sh

set -e

purpose="$1"

fail() {
  >&2 echo $@
  exit 1
}

# We support a limited set of platforms in our binary builds.
# Other platforms will need to build from source instead of using asdf.
if uname | grep -iq 'Linux'; then
  if uname -m | grep -iq 'x86_64'; then
    if getconf GNU_LIBC_VERSION > /dev/null 2>&1; then
      echo 'x86_64-unknown-linux-gnu'
    elif ldd --version 2>&1 | grep -iq musl; then
      echo 'x86_64-unknown-linux-musl'
    else
      fail "On Linux, the supported libc variants are: gnu, musl"
    fi
  elif uname -m | grep -iq 'aarch64'; then
    if ldd --version 2>&1 | grep -iq musl; then
      echo 'arm64-unknown-linux-musl'
    else
      fail "On arm64 Linux, the only supported libc variant is: musl"
    fi
  else
    fail "On Linux, the only arches currently supported are: x86_64, arm64"
  fi
elif uname | grep -iq 'FreeBSD'; then
  if uname -m | grep -iq 'amd64'; then
    echo 'x86_64-unknown-freebsd'
  else
    fail "On FreeBSD, the only arch currently supported is: x86_64"
  fi
elif uname | grep -iq 'Darwin'; then
  if uname -m | grep -iq 'x86_64'; then
    echo 'x86_64-apple-macosx'
  elif uname -m | grep -iq 'arm64'; then
    # LLVM static pre-built libraries are dual-arch, but we upload them
    # under the name of the x86_64 arch - so we fake that arch here only
    # for the case of determining paltform for downloading llvm-static libs.
    # For all other purposes we return the true platform triple.
    if [ "$purpose" = 'llvm-static' ]; then
      echo 'x86_64-apple-macosx'
    else
      echo 'arm64-apple-macosx'
    fi
  else
    fail "On Darwin, the only arches currently supported are: x86_64, arm64"
  fi
else
  fail "The only supported operating systems are: Linux, FreeBSD, Darwin"
fi
