NUM_OF_JOBS := 1
SPEC_FILES := $(shell find spec -name '*_spec.cr' -print | sort -n)
SPEC_TARGETS := $(shell seq -s " " -f "spec/%g" $(NUM_OF_JOBS))

spec:
	make -j $(SPEC_TARGETS) DOCKER_OPTIONS=-it

format-check:
	docker run \
		--rm \
		$(DOCKER_OPTIONS) \
		-v $(PWD):/workdir \
		-w /workdir \
		crystallang/crystal:latest \
		/bin/sh -c "crystal tool format --check"

.PHONY: spec format-check

spec/%:
	docker run \
		--rm \
		$(DOCKER_OPTIONS) \
		-v $(PWD):/workdir \
		-w /workdir \
		crystallang/crystal:latest \
		/bin/sh -c "crystal eval 'array = \"$(SPEC_FILES)\".split(\" \"); puts array.map_with_index{|e,i| {index: i, value: e}}.group_by{|e| e[:index] % ($(NUM_OF_JOBS))}[$* - 1].map(&.[](:value)).join(\" \")' | xargs -d \" \" -I{} /bin/sh -c 'echo \"\n\n=========================\n{}\"; crystal spec {}'"
