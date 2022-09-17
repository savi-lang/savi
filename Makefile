# By default, use a `debug` build of the Savi compiler,
# but this can be overridden by the caller to use a `release` build.
config?=debug

# Allow overriding the build dir (for example in Docker-based invocations).
BUILD?=build
MAKE_VAR_CACHE?=.make-var-cache

# Some convenience variables that set up the paths for the built Savi binaries.
SAVI=$(BUILD)/savi-$(config)
SPEC=$(BUILD)/savi-spec

CLANGXX?=clang++
CLANG?=clang

# Run the full CI suite.
ci: PHONY
	${MAKE} format.check
	${MAKE} spec.core.deps extra_args="--backtrace $(extra_args)"
	${MAKE} spec.all extra_args="--backtrace $(extra_args)"
	${MAKE} example.deps dir="examples/adventofcode/2018" extra_args="--backtrace $(extra_args)"
	${MAKE} example dir="examples/adventofcode/2018" extra_args="--backtrace $(extra_args)"
	${MAKE} example-eval

# Remove temporary/generated/downloaded files.
clean: PHONY
	rm -rf $(BUILD) $(MAKE_VAR_CACHE) lib/libsavi_runtime

# Run the full test suite.
spec.all: PHONY spec.compiler.all spec.language spec.core spec.unit.all spec.integration.all

# Run the specs that are written in markdown (mostly compiler pass tests).
# Run the given compiler-spec target (or all targets).
spec.compiler: PHONY SAVI
	echo && $(SAVI) compilerspec "spec/compiler/$(name).savi.spec.md" $(extra_args)
spec.compiler.all: PHONY $(SAVI)
	find "spec/compiler" -name '*.savi.spec.md' | sort | xargs -I'{}' sh -c \
		'echo && $(SAVI) compilerspec {} $(extra_args) || exit 255'

# Run the specs for the basic language semantics.
spec.language: PHONY SAVI
	echo && $(SAVI) run --cd spec/language $(extra_args)

# Run the specs for the core package.
spec.core: PHONY SAVI
	echo && $(SAVI) run --cd spec/core $(extra_args)

# Update deps for the specs for the core package.
spec.core.deps: PHONY SAVI
	echo && $(SAVI) deps update --cd spec/core $(extra_args)

# Run the specs for the core package in lldb for debugging.
spec.core.lldb: PHONY SAVI
	echo && $(SAVI) build --cd spec/core $(extra_args) && \
		lldb -o run -- spec/core/bin/spec

# Run the specs that are written in Crystal (mostly compiler unit tests),
# narrowing to those with the given name (or all of them).
spec.unit: PHONY SPEC
	echo && $(SPEC) -v -e "$(name)"
spec.unit.all: PHONY SPEC
	echo && $(SPEC)

# Run the integration tests, which invoke the compiler in a real directory.
spec.integration: PHONY SAVI
	echo && spec/integration/run-one.sh "$(name)" $(SAVI)
spec.integration.all: PHONY SAVI
	echo && spec/integration/run-all.sh $(SAVI)

# Check formatting of *.savi source files.
format.check: PHONY SAVI
	echo && $(SAVI) format --check --backtrace

# Fix formatting of *.savi source files.
format: PHONY SAVI
	echo && $(SAVI) format --backtrace

# Generate FFI code.
ffigen: PHONY SAVI
	echo && $(SAVI) ffigen "$(header)" $(extra_args) --backtrace

# Evaluate a Hello World example.
example-eval: PHONY SAVI
	echo && $(SAVI) eval 'env.out.print("Hello, World!")' --backtrace

# Compile and run the user program binary in the given directory.
example: PHONY SAVI
	echo && $(SAVI) run --cd "$(dir)" $(extra_args)

# Compile the files in the given directory.
example.compile: PHONY SAVI
	echo && $(SAVI) --cd "$(dir)" $(extra_args)

# Update deps for the specs for the given example directory.
example.deps: PHONY SAVI
	echo && $(SAVI) deps update --cd "$(dir)" $(extra_args)

# Compile the vscode extension.
vscode: PHONY SAVI
	cd tooling/vscode && npm run-script compile || npm install

##
# General utilities

.PHONY: PHONY

SAVI: $(SAVI) lib/libsavi_runtime
SPEC: $(SPEC) lib/libsavi_runtime

# This is a bit of Makefile voodoo we use to allow us to use the value
# of a variable to invalidate a target file when it changes.
# This lets us force make to rebuild things when that variable changes.
# See https://stackoverflow.com/a/26147844
define MAKE_VAR_CACHE_FOR

$(MAKE_VAR_CACHE)/$1: PHONY
	@mkdir -p $(MAKE_VAR_CACHE)
	@if [ '$(shell cat $(MAKE_VAR_CACHE)/$1 2> /dev/null)' = '$($1)' ]; then echo; else \
		/usr/bin/env echo -n $($1) > $(MAKE_VAR_CACHE)/$1; fi

endef

##
# Build-related targets

# We expect a CI release build to specify the version externally,
# so here we just default to unknown if it was not specified.
SAVI_VERSION?=unknown

# Use an external shell script to detect the platform.
# Currently the platform representation takes the form of an LLVM "triple".
LLVM_STATIC_PLATFORM?=$(shell ./platform.sh llvm-static)
TARGET_PLATFORM?=$(shell ./platform.sh host)
CLANG_TARGET_PLATFORM?=$(TARGET_PLATFORM)

# Specify where to download our pre-built LLVM/clang static libraries from.
# This needs to get bumped explicitly here when we do a new LLVM build.
LLVM_STATIC_RELEASE_URL?=https://github.com/savi-lang/llvm-static/releases/download/v14.0.3-20220506
$(eval $(call MAKE_VAR_CACHE_FOR,LLVM_STATIC_RELEASE_URL))

# Specify where to download our pre-built runtime bitcode from.
# This needs to get bumped explicitly here when we do a new runtime build.
RUNTIME_BITCODE_RELEASE_URL?=https://github.com/savi-lang/runtime-bitcode/releases/download/v0.20220912.1
$(eval $(call MAKE_VAR_CACHE_FOR,RUNTIME_BITCODE_RELEASE_URL))

# This is the path where we look for the LLVM pre-built static libraries to be,
# including the llvm-config utility used to print information about them.
# By default this is set up
LLVM_PATH?=$(BUILD)/llvm-static
LLVM_CONFIG?=$(LLVM_PATH)/bin/llvm-config

# Determine which flavor of the C++ standard library to link against.
# We choose libstdc++ on Linux and DragonFly, and libc++ on FreeBSD and MacOS.
ifneq (,$(findstring linux,$(TARGET_PLATFORM)))
	LIB_CXX_KIND?=stdc++
else ifneq (,$(findstring dragonfly,$(TARGET_PLATFORM)))
	LIB_CXX_KIND?=stdc++
else
	LIB_CXX_KIND?=c++
endif

# Find the libraries we need to link against.
# We look first for a static library path, or fallback to specifying it as -l
# which will cause the linker to locate it as a dynamic library.
LIB_GC?=$(shell find /usr /opt -name libgc.a 2> /dev/null | head -n 1 | grep . || echo -lgc)
LIB_EVENT?=$(shell find /usr /opt -name libevent.a 2> /dev/null | head -n 1 | grep . || echo -levent)
LIB_PCRE?=$(shell find /usr /opt -name libpcre.a 2> /dev/null | head -n 1 | grep . || echo -lpcre)

# Collect the list of libraries to link against (depending on the platform).
# These are the libraries used by the Crystal runtime.

CRYSTAL_RT_LIBS+=$(LIB_GC)
CRYSTAL_RT_LIBS+=$(LIB_EVENT)
CRYSTAL_RT_LIBS+=$(LIB_PCRE)
ifneq (,$(findstring macos,$(TARGET_PLATFORM)))
	CRYSTAL_RT_LIBS+=-liconv
endif

ifneq (,$(findstring freebsd,$(TARGET_PLATFORM)))
	CRYSTAL_RT_LIBS+=-L/usr/local/lib
endif

ifneq (,$(findstring dragonfly,$(TARGET_PLATFORM)))
	CRYSTAL_RT_LIBS+=-L/usr/local/lib
endif

CRYSTAL_RT_LIBS+=-l$(LIB_CXX_KIND)

ifneq (,$(findstring dragonfly,$(TARGET_PLATFORM)))
	# On DragonFly:
	#
	# * -flto=thin is not accepted
	# * we have to explicitly state the linker
	# * we cannot link libclang statically
	SAVI_LD_FLAGS=-fuse-ld=lld -L/usr/lib -L/usr/local/lib -L/usr/lib/gcc80
	LIB_CLANG=-lclang
else
	SAVI_LD_FLAGS=-flto=thin -no-pie
	LIB_CLANG=`sh -c 'ls $(LLVM_PATH)/lib/libclang*.a'`
endif


# This is the path to the Crystal standard library source code,
# including the LLVM extensions C++ file we need to build and link.
CRYSTAL_PATH?=$(shell env $(shell crystal env) printenv CRYSTAL_PATH | rev | cut -d ':' -f 1 | rev)

# Download the runtime bitcode library we have built separately.
# See github.com/savi-lang/runtime-bitcode for more info.
lib/libsavi_runtime: $(MAKE_VAR_CACHE)/RUNTIME_BITCODE_RELEASE_URL
	rm -rf $@-tmp
	mkdir -p $@-tmp
	cd $@-tmp && curl -L --fail -sS \
		"${RUNTIME_BITCODE_RELEASE_URL}/libsavi_runtime.tar.gz" \
	| tar -xzvf -
	rm -rf $@
	mv $@-tmp $@
	touch $@

# Download the static LLVM/clang libraries we have built separately.
# See github.com/savi-lang/llvm-static for more info.
# This target will be unused if someone overrides the LLVM_PATH variable
# to point to an LLVM installation they obtained by some other means.
$(BUILD)/llvm-static: $(MAKE_VAR_CACHE)/LLVM_STATIC_RELEASE_URL
	rm -rf $@-tmp
	mkdir -p $@-tmp
	cd $@-tmp && curl -L --fail -sS \
		"${LLVM_STATIC_RELEASE_URL}/${LLVM_STATIC_PLATFORM}-llvm-static.tar.gz" \
	| tar -xzvf -
	rm -rf $@
	mv $@-tmp $@
	touch $@

# Build the Crystal LLVM C bindings extensions as LLVM bitcode.
# This bitcode needs to get linked into our Savi compiler executable.
$(BUILD)/llvm_ext.bc: $(LLVM_PATH)
	mkdir -p `dirname $@`
	${CLANGXX} -v -emit-llvm -g \
		-c `$(LLVM_CONFIG) --cxxflags` \
		-target $(CLANG_TARGET_PLATFORM) \
		$(CRYSTAL_PATH)/llvm/ext/llvm_ext.cc \
		-o $@

# Build the extra Savi LLVM extensions as LLVM bitcode.
# This bitcode needs to get linked into our Savi compiler executable.
$(BUILD)/llvm_ext_for_savi.bc: $(LLVM_PATH) $(shell find src/savi/ext/llvm/for_savi -name '*.cc')
	mkdir -p `dirname $@`
	${CLANGXX} -v -emit-llvm -g \
		-c `$(LLVM_CONFIG) --cxxflags` \
		-target $(CLANG_TARGET_PLATFORM) \
		src/savi/ext/llvm/for_savi/main.cc \
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
		LLVM_DEFAULT_TARGET=$(TARGET_PLATFORM) \
		crystal build $< -o $(shell echo $@ | rev | cut -f 2- -d '.' | rev) \
			--release --stats --error-trace --cross-compile --target $(TARGET_PLATFORM)

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
		LLVM_DEFAULT_TARGET=$(TARGET_PLATFORM) \
		crystal build $< -o $(shell echo $@ | rev | cut -f 2- -d '.' | rev) \
			--debug --stats --error-trace --cross-compile --target $(TARGET_PLATFORM)

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
		LLVM_DEFAULT_TARGET=$(TARGET_PLATFORM) \
		crystal build $< -o $(shell echo $@ | rev | cut -f 2- -d '.' | rev) \
			--debug --stats --error-trace --cross-compile --target $(TARGET_PLATFORM)

# Build the Savi compiler executable, by linking the above targets together.
# This variant of the target compiles in release mode.
$(BUILD)/savi-release: $(BUILD)/savi-release.o $(BUILD)/llvm_ext.bc $(BUILD)/llvm_ext_for_savi.bc
	mkdir -p `dirname $@`
	${CLANG} -O3 -o $@ $(SAVI_LD_FLAGS) \
		$(BUILD)/savi-release.o $(BUILD)/llvm_ext.bc $(BUILD)/llvm_ext_for_savi.bc \
		${CRYSTAL_RT_LIBS} \
		-target $(CLANG_TARGET_PLATFORM) \
		`sh -c 'ls $(LLVM_PATH)/lib/liblld*.a'` \
		`$(LLVM_CONFIG) --ldflags ` \
		`$(LLVM_CONFIG) --libfiles --link-static` \
		`$(LLVM_CONFIG) --system-libs --link-static` \
		$(LIB_CLANG)


# Build the Savi compiler executable, by linking the above targets together.
# This variant of the target compiles in debug mode.
$(BUILD)/savi-debug: $(BUILD)/savi-debug.o $(BUILD)/llvm_ext.bc $(BUILD)/llvm_ext_for_savi.bc
	mkdir -p `dirname $@`
	${CLANG} -O0 -o $@ $(SAVI_LD_FLAGS) \
		$(BUILD)/savi-debug.o $(BUILD)/llvm_ext.bc $(BUILD)/llvm_ext_for_savi.bc \
		 ${CRYSTAL_RT_LIBS} \
		-target $(CLANG_TARGET_PLATFORM) \
		`sh -c 'ls $(LLVM_PATH)/lib/liblld*.a'` \
		`$(LLVM_CONFIG) --ldflags ` \
		`$(LLVM_CONFIG) --libfiles --link-static` \
		`$(LLVM_CONFIG) --system-libs --link-static` \
		$(LIB_CLANG)
	if uname | grep -iq 'Darwin'; then dsymutil $@; fi

# Build the Savi specs executable, by linking the above targets together.
# This variant of the target will be used when running tests.
$(BUILD)/savi-spec: $(BUILD)/savi-spec.o $(BUILD)/llvm_ext.bc $(BUILD)/llvm_ext_for_savi.bc
	mkdir -p `dirname $@`
	${CLANG} -O0 -o $@ $(SAVI_LD_FLAGS) \
		$(BUILD)/savi-spec.o $(BUILD)/llvm_ext.bc $(BUILD)/llvm_ext_for_savi.bc \
		 ${CRYSTAL_RT_LIBS} \
		-target $(CLANG_TARGET_PLATFORM) \
		`sh -c 'ls $(LLVM_PATH)/lib/liblld*.a'` \
		`$(LLVM_CONFIG) --ldflags ` \
		`$(LLVM_CONFIG) --libfiles --link-static` \
		`$(LLVM_CONFIG) --system-libs --link-static` \
		$(LIB_CLANG)
	if uname | grep -iq 'Darwin'; then dsymutil $@; fi
