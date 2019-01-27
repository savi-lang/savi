# Prepare a docker container that has everything needed for development.
# It runs in the background indefinitely, waiting for `docker exec` commands.
ready: Dockerfile
	docker build --tag mare-dev .
	docker rm -f mare-dev || echo "the mare-dev container wasn't running"
	docker run --name mare-dev -v $(shell pwd):/opt/code -d --rm mare-dev tail -f /dev/null
	@echo "the mare-dev container is ready!"

# Run the test suite.
test:
	docker exec -ti mare-dev make test.inner
test.inner: src spec
	crystal build --debug --link-flags="-lponyrt" spec/spec_helper.cr -o ./spec.bin
	echo && ./spec.bin && rm spec.bin || rm spec.bin
