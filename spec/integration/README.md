# Savi Integration Tests

This folder contains a collection of subdirectories, with each subdirectory being an integration test case.

To test a case, the Savi compiler will be invoked in that subdirectory by the integration test runner, which will observe the effects of the invocation and validate that they match the expected effects.

Each subdirectory contains Savi source files as well as some testing-related files/folders to let the integration test runner know exactly what and how to test. The integration test runner will choose a testing strategy based on which testing-related files/folders are present. See the sections describing the different testing strategies below for more information.

## Error output tests

If the test case subdirectory contains a `savi.errors.txt` file, then the compiler invocation is expected to fail, and produce error output that exactly matches the content of that file.

If the error output doesn't exactly match the expected output, the test case will fail.

By convention, test case subdirectories like this are named with the `error-` prefix, followed by the name of the pass that is expected to produce the errors, followed by a brief description of the error we are testing for.

For example, the test case subdirectory `error-manifests-non-unique-names` is an error output test case, testing errors produced in the `manifests` pass, where what is being tested are the errors emitted when the compiler encounters non-unique manifest names.

## Auto-fix tests

If the test case subdirectory contains a `savi.fix.before.dir` subdirectory, a `savi.fix.after.dir` subdirectory, and an `savi.errors.txt` file, then like the error output tests, the initial compiler invocation is expected to fail with a specified error output, but the compiler witll be invoked again with the `--fix` flag, wherein it is expected to fix all of those errors automatically and succeed in compiling the program.

Before the invocation, source files from `savi.fix.before.dir` will be copied into the directory. After the invocation, the resulting fixed files will be compared with the source files in `savi.fix.after.dir` to confirm that the contents of each compared file exactly matches the corresponding "after" file. If any such file is missing, or its content doesn't exactly match, the test case will fail. After the test is finished (succeed or fail), the files that were copied from the "before" directory are removed, to leave the test case directory in an empty state without extra files to be tracked in git.

By convention, test case subdirectories like this are named with the `fix-` prefix, followed by the name of the pass that is expected to produce the auto-fixable errors, followed by a brief description of the error we are testing for.

For example, the test case subdirectory `fix-manifests-missing-transitive-deps` is an error output test case, testing auto-fixable errors produced in the `manifests` pass, where what is being tested is the compiler being able to auto-fix missing transitive dependencies in the manifest being compiled.
