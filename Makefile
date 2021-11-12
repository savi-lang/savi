# By default, use a `debug` build of the Savi compiler,
# but this can be overridden by the caller to use a `release` build.
config?=debug

# Allow overriding the build dir (for example in Docker-based invocations).
BUILD?=build

# Some convenience variables that set up the paths for the built Savi binaries.
SAVI=$(BUILD)/savi-$(config)
SPEC=$(BUILD)/savi-spec

# Prepare a docker container that has everything needed for development.
# It runs in the background indefinitely, waiting for `docker exec` commands.
ready: PHONY Dockerfile
	docker build --target dev --tag savi-dev .
	docker rm -f savi-dev || echo "the savi-dev container wasn't running"
	docker run --name savi-dev -v $(shell pwd):/opt/code -d --rm --memory 4g -p 8080 savi-dev tail -f /dev/null
	@echo "the savi-dev container is ready!"

# Run the full CI suite.
ci: PHONY
	make format-check
	make compiler-spec.all
	make test extra_args="$(extra_args)"
	make example-run dir="examples/adventofcode/2018" extra_args="--backtrace"

# Run the test suite.
test: PHONY $(SPEC)
	echo && $(SPEC) $(extra_args)

# Run a narrow target within the test suite.
test.narrow: PHONY
	echo && $(SPEC) -v -e "$(target)"

# Run the given compiler-spec target.
compiler-spec: PHONY $(SAVI)
	echo && $(SAVI) compilerspec "$(target)" $(extra_args)
compiler-spec.all: PHONY
	find "spec/compiler" -name '*.savi.spec.md' | xargs -I '{}' sh -c 'make compiler-spec target="{}" extra_args="'$(extra_args)'" || exit 255'

# Check formatting of *.savi source files.
format-check: PHONY $(SAVI)
	echo && $(SAVI) format --check --backtrace

# Fix formatting of *.savi source files.
format: PHONY $(SAVI)
	echo && $(SAVI) format --backtrace

# Generate FFI code.
ffigen: PHONY $(SAVI)
	echo && $(SAVI) ffigen "$(header)" --backtrace

# Evaluate a Hello World example.
example-eval: PHONY $(SAVI)
	echo && $(SAVI) eval 'env.out.print("Hello, World!")'

# Run the files in the given directory.
example-run: PHONY $(SAVI)
	echo && cd "$(dir)" && $(shell pwd)/$(SAVI) run $(extra_args)

# Compile the files in the given directory.
example-compile: PHONY $(SAVI)
	echo && cd "$(dir)" && $(shell pwd)/$(SAVI) $(extra_args)

# Compile and run the user program binary in the given directory.
example: example-compile
	echo && "$(dir)/main"

# Compile and run the user program binary in the given directory under LLDB.
example-lldb: example-compile
	echo && lldb -o run -- "$(dir)/main"

# Compile the language server image and vscode extension.
vscode: PHONY
	docker build . --tag jemc/savi
	cd tooling/vscode && npm run-script compile || npm install

##
# General utilities

.PHONY: PHONY

# This is a bit of Makefile voodoo we use to allow us to use the value
# of a variable to invalidate a target file when it changes.
# This lets us force make to rebuild things when that variable changes.
# See https://stackoverflow.com/a/26147844
define MAKE_VAR_CACHE

.make-var-cache/$1: PHONY
	@mkdir -p .make-var-cache
	@if [ '$(shell cat .make-var-cache/$1 2> /dev/null)' = '$($1)' ]; then echo; else \
		/bin/echo -n $($1) > .make-var-cache/$1; fi

endef

##
# Build-related targets

# We expect a CI release build to specify the version externally,
# so here we just default to unknown if it was not specified.
SAVI_VERSION?=unknown

# Use an external shell script to detect the platform.
# Currently the platform representation takes the form of an LLVM "triple".
LLVM_PLATFORM?=$(shell ./platform.sh)

# Specify where to download our pre-built LLVM/clang static libraries from.
# This needs to get bumped explicitly here when we do a new LLVM build.
LLVM_STATIC_RELEASE_URL?=https://github.com/savi-lang/llvm-static/releases/download/20211111
$(eval $(call MAKE_VAR_CACHE,LLVM_STATIC_RELEASE_URL))

# Specify where to download our pre-built LLVM/clang static libraries from.
# This needs to get bumped explicitly here when we do a new LLVM build.
RUNTIME_BITCODE_RELEASE_URL?=https://github.com/savi-lang/runtime-bitcode/releases/download/20211101
$(eval $(call MAKE_VAR_CACHE,RUNTIME_BITCODE_RELEASE_URL))

# This is the path where we look for the LLVM pre-built static libraries to be,
# including the llvm-config utility used to print information about them.
# By default this is set up
LLVM_PATH?=$(BUILD)/llvm-static
LLVM_CONFIG?=$(LLVM_PATH)/bin/llvm-config

# Find the libraries we need to link against.
# We look first for a static library path, or fallback to specifying it as -l
# which will cause the linker to locate it as a dyanmic library.
LIB_GC?=$(shell find /usr -name libgc.a 2> /dev/null | head -n 1 | grep . || echo -lgc)
LIB_EVENT?=$(shell find /usr -name libevent.a 2> /dev/null | head -n 1 | grep . || echo -levent)
LIB_PCRE?=$(shell find /usr -name libpcre.a 2> /dev/null | head -n 1 | grep . || echo -lpcre)

# Collect the list of libraries to link against (depending on the platform).
# These are the libraries used by the Crystal runtime.
CRYSTAL_RT_LIBS+=$(LIB_GC)
CRYSTAL_RT_LIBS+=$(LIB_EVENT)
CRYSTAL_RT_LIBS+=$(LIB_PCRE)
ifneq (,$(findstring macos,$(LLVM_PLATFORM)))
	CRYSTAL_RT_LIBS+="-liconv"
endif

# This is the path to the Crystal standard library source code,
# including the LLVM extensions C++ file we need to build and link.
CRYSTAL_PATH?=$(shell env $(shell crystal env) printenv CRYSTAL_PATH | rev | cut -d ':' -f 1 | rev)

# Download the static LLVM/clang libraries we have built separately.
# See github.com/savi-lang/llvm-static for more info.
# This target will be unused if someone overrides the LLVM_PATH variable
# to point to an LLVM installation they obtained by some other means.
lib/libsavi_runtime.bc: .make-var-cache/RUNTIME_BITCODE_RELEASE_URL
	rm -f $@.tmp
	curl -L --fail -sS \
		"${RUNTIME_BITCODE_RELEASE_URL}/${LLVM_PLATFORM}-libponyrt.bc" \
	> $@.tmp
	rm -f $@
	mv $@.tmp $@
	touch $@

# Download the static LLVM/clang libraries we have built separately.
# See github.com/savi-lang/llvm-static for more info.
# This target will be unused if someone overrides the LLVM_PATH variable
# to point to an LLVM installation they obtained by some other means.
$(BUILD)/llvm-static: .make-var-cache/LLVM_STATIC_RELEASE_URL
	rm -rf $@-tmp
	mkdir -p $@-tmp
	cd $@-tmp && curl -L --fail -sS \
		"${LLVM_STATIC_RELEASE_URL}/${LLVM_PLATFORM}-llvm-static.tar.gz" \
	| tar -xzvf -
	rm -rf $@
	mv $@-tmp $@
	touch $@

# Build the Crystal LLVM C bindings extensions as LLVM bitcode.
# This bitcode needs to get linked into our Savi compiler executable.
$(BUILD)/llvm_ext.bc: $(LLVM_PATH)
	mkdir -p `dirname $@`
	clang++ -v -emit-llvm -c `$(LLVM_CONFIG) --cxxflags` \
		$(CRYSTAL_PATH)/llvm/ext/llvm_ext.cc \
		-o $@

# Build the Savi compiler object file, based on the Crystal source code.
# We trick the Crystal compiler into thinking we are cross-compiling,
# so that it won't try to run the linker for us - we want to run it ourselves.
# This variant of the target compiles in release mode.
$(BUILD)/savi-release.o: main.cr $(LLVM_PATH) $(shell find src lib -name '*.cr')
	mkdir -p `dirname $@`
	env \
		SAVI_VERSION=$(SAVI_VERSION) \
		SAVI_LLVM_VERSION=`$(LLVM_CONFIG) --version` \
		LLVM_CONFIG=$(LLVM_CONFIG) \
		crystal build $< -o $(shell echo $@ | rev | cut -f 2- -d '.' | rev) \
			--release --stats --error-trace --cross-compile --target=$(LLVM_PLATFORM)

# Build the Savi compiler object file, based on the Crystal source code.
# We trick the Crystal compiler into thinking we are cross-compiling,
# so that it won't try to run the linker for us - we want to run it ourselves.
# This variant of the target compiles in debug mode.
$(BUILD)/savi-debug.o: main.cr $(LLVM_PATH) $(shell find src lib -name '*.cr')
	mkdir -p `dirname $@`
	env \
		SAVI_VERSION=$(SAVI_VERSION) \
		SAVI_LLVM_VERSION=`$(LLVM_CONFIG) --version` \
		LLVM_CONFIG=$(LLVM_CONFIG) \
		crystal build $< -o $(shell echo $@ | rev | cut -f 2- -d '.' | rev) \
			--debug --stats --error-trace --cross-compile --target=$(LLVM_PLATFORM)

# Build the Savi specs object file, based on the Crystal source code.
# We trick the Crystal compiler into thinking we are cross-compiling,
# so that it won't try to run the linker for us - we want to run it ourselves.
# This variant of the target will be used when running tests.
$(BUILD)/savi-spec.o: spec/all.cr $(LLVM_PATH) $(shell find src lib spec -name '*.cr')
	mkdir -p `dirname $@`
	env \
		SAVI_VERSION=$(SAVI_VERSION) \
		SAVI_LLVM_VERSION=`$(LLVM_CONFIG) --version` \
		LLVM_CONFIG=$(LLVM_CONFIG) \
		crystal build $< -o $(shell echo $@ | rev | cut -f 2- -d '.' | rev) \
			--debug --stats --error-trace --cross-compile --target=$(LLVM_PLATFORM)

# Build the Savi compiler executable, by linking the above targets together.
# This variant of the target compiles in release mode.
$(BUILD)/savi-release: $(BUILD)/savi-release.o $(BUILD)/llvm_ext.bc lib/libsavi_runtime.bc
	mkdir -p `dirname $@`
	clang -O0 -o $@ -flto=thin -fPIC $^ ${CRYSTAL_RT_LIBS} -lstdc++ \
		`sh -c 'ls $(LLVM_PATH)/lib/libclang*.a'` \
		`$(LLVM_CONFIG) --libfiles --link-static` \
		`$(LLVM_CONFIG) --system-libs --link-static`
	$@ --version

# Build the Savi compiler executable, by linking the above targets together.
# This variant of the target compiles in debug mode.
$(BUILD)/savi-debug: $(BUILD)/savi-debug.o $(BUILD)/llvm_ext.bc lib/libsavi_runtime.bc
	mkdir -p `dirname $@`
	clang -O3 -o $@ -flto=thin -fPIC $^ ${CRYSTAL_RT_LIBS} -lstdc++ \
		`sh -c 'ls $(LLVM_PATH)/lib/libclang*.a'` \
		`$(LLVM_CONFIG) --libfiles --link-static` \
		`$(LLVM_CONFIG) --system-libs --link-static`
	$@ --version

# Build the Savi specs executable, by linking the above targets together.
# This variant of the target will be used when running tests.
$(BUILD)/savi-spec: $(BUILD)/savi-spec.o $(BUILD)/llvm_ext.bc lib/libsavi_runtime.bc
	mkdir -p `dirname $@`
	clang -O0 -o $@ -flto=thin -fPIC $^ ${CRYSTAL_RT_LIBS} -lstdc++ \
		`sh -c 'ls $(LLVM_PATH)/lib/libclang*.a'` \
		`$(LLVM_CONFIG) --libfiles --link-static` \
		`$(LLVM_CONFIG) --system-libs --link-static`
