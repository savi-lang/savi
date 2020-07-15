# Mare

<a href="https://openclipart.org/detail/191499/horse"><img alt="The ungui-angui-pede, a mascot for Mare" src="./assets/mascot.svg" width="100px" /></a>

[![CircleCI](https://circleci.com/gh/jemc/mare.svg?style=shield)](https://circleci.com/gh/jemc/mare) [![Docker](https://img.shields.io/docker/cloud/automated/jemc/mare.svg)](https://hub.docker.com/r/jemc/mare)

Mare is a reimagining of the [Pony](https://www.ponylang.io/) language.

The goal is to create a language with all the desirable features of Pony, while simultaneously being more approachable to newcomers and more extensible for power users.

It's an early work in progress, but it can already compile and run basic programs.

Check out the [feature roadmap](./ROADMAP.md) and [goals summary](./GOALS.md) for more information on where this project is headed.

## Try It!

There are a few ways you can try out Mare. All of them assume you have a working `docker` installation, so take a moment to take care of that first.

First, just to prove the basics, you can use the `eval` subcommand of the docker image to compile a program:

```sh
docker run --rm jemc/mare eval 'env.out.print("Hello, World!")'
# Prints "Hello, World!"
```

Beyond that, you can also use the docker image to compile a source code directory by mounting the directory into the container, like so:

```sh
# Compile the program.
docker run --rm -v ${PATH_TO_YOUR_CODE}:/opt/code jemc/mare
# Run the program.
${PATH_TO_YOUR_CODE}/main
```

If you're a VS Code user, you may be interested to install our [language extension for that editor](./tooling/vscode), which includes both syntax highlighting and some Intellisense features via using the docker image as an LSP server.

We also have [a vim/nvim extension](./tooling/coc-nvim) as well.

Finally, if you want to contribute to Mare, read on through the next section to learn about some of the basic development commands.

## Developing

To work on this project, you'll need `docker` and `make`. You may also want to have `lldb` for debugging.

To get started, clone the project to your development machine, then run one of the following commands within the project working directory:

- Run `make ready` to prepare a docker container that has everything needed for development activities. Do this before running any of the other following commands:

- Run `make test` to run the test suite.

- Run `make example-run dir="/opt/code/examples/adventofcode/2018` to compile and run from the sources in `./examples/adventofcode/2018` directory (or similarly for any other example code directory).

- Run `make example-lldb` to do the same as above, but run inside `lldb` to allow you to breakpoint and step through code.
