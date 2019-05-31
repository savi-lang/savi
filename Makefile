PHONY:

# Prepare a docker container that has everything needed for development.
# It runs in the background indefinitely, waiting for `docker exec` commands.
ready: PHONY Dockerfile
	docker build --target dev --tag mare-dev .
	docker rm -f mare-dev || echo "the mare-dev container wasn't running"
	docker run --name mare-dev -v $(shell pwd):/opt/code -d --rm mare-dev tail -f /dev/null
	@echo "the mare-dev container is ready!"

# Run the test suite.
test: PHONY
	docker exec -ti mare-dev make extra_args="$(extra_args)" test.inner
/tmp/bin/spec: $(shell find src -name '*.cr') $(shell find spec -name '*.cr')
	mkdir -p /tmp/bin
	crystal build --debug --link-flags="-lponyrt" spec/spec_helper.cr -o $@
test.inner: PHONY /tmp/bin/spec
	echo && /tmp/bin/spec $(extra_args)

# Compile and run the mare binary in the `example` subdirectory.
example: PHONY
	docker exec -ti mare-dev make extra_args="$(extra_args)" example/main
	echo && docker exec -ti mare-dev example/main || true
example-lldb: PHONY
	docker exec -ti mare-dev make extra_args="$(extra_args)" example/main
	echo && lldb -o run -- example/main # TODO: run this within docker when alpine supports lldb package outside of edge
example-mare-callgrind: PHONY
	docker exec -ti mare-dev make extra_args="$(extra_args)" example-mare-callgrind.inner
/tmp/bin/mare: main.cr $(shell find src -name '*.cr')
	mkdir -p /tmp/bin
	crystal build --debug --link-flags="-lponyrt" main.cr -o $@
example/main: /tmp/bin/mare $(shell find example -name '*.mare')
	echo && cd example && /tmp/bin/mare
/tmp/callgrind.out: /tmp/bin/mare
	echo && cd example && valgrind --tool=callgrind --callgrind-out-file=$@ $<
example-mare-callgrind.inner: /tmp/callgrind.out PHONY
	/usr/bin/callgrind_annotate $< | less
