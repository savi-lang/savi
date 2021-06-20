PHONY:

# Prepare a docker container that has everything needed for development.
# It runs in the background indefinitely, waiting for `docker exec` commands.
ready: PHONY Dockerfile
	docker build --target dev --tag mare-dev .
	docker rm -f mare-dev || echo "the mare-dev container wasn't running"
	docker run --name mare-dev -p 8080:8080 -v $(shell pwd):/opt/code -d --rm --memory 4g mare-dev tail -f /dev/null
	@echo "the mare-dev container is ready!"

# Run the full CI suite.
ci: PHONY
	make compiler-spec.all
	make test extra_args="$(extra_args)"
	make example-run dir="examples/adventofcode/2018" extra_args="--backtrace"

# Run the test suite.
test: PHONY
	docker exec -ti mare-dev make extra_args="$(extra_args)" test.inner
/tmp/bin/spec: $(shell find lib -name '*.cr') $(shell find src -name '*.cr') $(shell find spec -name '*.cr')
	mkdir -p /tmp/bin
	crystal build --debug spec/all.cr -o $@
test.inner: PHONY /tmp/bin/spec
	echo && /tmp/bin/spec $(extra_args)

# Run a narrow target within the test suite.
test.narrow: PHONY
	docker exec -ti mare-dev make target="$(target)" extra_args="$(extra_args)" test.narrow.inner
test.narrow.inner: PHONY
	crystal spec spec/spec_helper.cr "$(target)" $(extra_args)

# Run the given compiler-spec target.
compiler-spec: PHONY
	docker exec -i mare-dev make target="$(target)" extra_args="$(extra_args)" compiler-spec.inner
compiler-spec.inner: PHONY /tmp/bin/mare
	echo && /tmp/bin/mare compilerspec "$(target)" $(extra_args)
compiler-spec.all: PHONY
	find "spec/compiler" -name '*.mare.spec.md' | xargs -I '{}' sh -c 'make compiler-spec target="{}" extra_args="'$(extra_args)'" || exit 255'

# Evaluate a Hello World example.
example-eval: PHONY
	docker exec -ti mare-dev make extra_args="$(extra_args)" example-eval.inner
example-eval.inner: PHONY /tmp/bin/mare
	echo && /tmp/bin/mare eval 'env.out.print("Hello, World!")'

# Run the files in the given directory.
example-run: PHONY
	docker exec -ti mare-dev make dir="$(dir)" extra_args="$(extra_args)" example-run.inner
example-run.inner: PHONY /tmp/bin/mare
	echo && cd "/opt/code/$(dir)" && /tmp/bin/mare run $(extra_args)

# Compile the files in the given directory.
example-compile: PHONY
	docker exec -ti mare-dev make dir="$(dir)" extra_args="$(extra_args)" example-compile.inner
example-compile.inner: PHONY /tmp/bin/mare
	echo && cd "/opt/code/$(dir)" && /tmp/bin/mare $(extra_args)

# Compile and run the mare binary in the given directory.
example: example-compile
	echo && docker exec -ti mare-dev "$(dir)/main" || true
example-lldb: example-compile
	echo && lldb -o run -- "$(dir)/main" # TODO: run this within docker when alpine supports lldb package outside of edge
example-mare-callgrind: PHONY
	docker exec -ti mare-dev make extra_args="$(extra_args)" example-mare-callgrind.inner
/tmp/bin/mare: main.cr $(shell find lib -name '*.cr') $(shell find src -name '*.cr')
	mkdir -p /tmp/bin
	crystal build --debug main.cr --error-trace -o $@
	ldd /tmp/bin/mare | grep libponyrt # prove that libponyrt was actually linked
/tmp/callgrind.out: /tmp/bin/mare
	echo && cd example && valgrind --tool=callgrind --callgrind-out-file=$@ $<
example-mare-callgrind.inner: /tmp/callgrind.out PHONY
	/usr/bin/callgrind_annotate $< | less

# Compile the language server image and vscode extension.
vscode: PHONY
	docker build . --tag jemc/mare
	cd tooling/vscode && npm run-script compile || npm install
