# Savi Integration Tests

This folder contains a collection of subdirectories, with each subdirectory being an integration test case.

To test a case, the Savi compiler will be invoked in that subdirectory by the integration test runner, which will observe the effects of the invocation and validate that they match the expected effects.

Each subdirectory contains Savi source files as well as some testing-related files/folders to let the integration test runner know exactly what and how to test. The integration test runner will choose a testing strategy based on which testing-related files/folders are present. See the sections describing the different testing strategies below for more information.

## Error output

If the test case subdirectory contains a `savi.errors.txt` file, then the compiler invocation is expected to fail, and produce error output that exactly matches the content of that file.

If the error output doesn't exactly match the expected output, the test case will fail.

By convention, test case subdirectories like this are named with the `error-` prefix, followed by the name of the pass that is expected to produce the errors, followed by a brief description of the error we are testing for.

For example, the test case subdirectory `error-manifests-non-unique-names` is an error output test case, testing errors produced in the `manifests` pass, where the errors under test relate with the compiler rejecting non-unique manifest names.
