# Mare

<a href="https://openclipart.org/detail/191499/horse"><img alt="The ungui-angui-pede, a mascot for Mare" src="https://openclipart.org/download/191499/1393759624.svg" width="100px" /></a>

Mare is a reimagining of the [Pony](https://www.ponylang.io/) language.

The goal is to create a language with all the desirable features of Pony, while simultaneously being more approachable to newcomers and more extensible for power users.

It's an early work in progress, but it can already compile and run basic programs.

Check out the [feature roadmap](./ROADMAP.md) and [goals summary](./GOALS.md) for more information on where this project is headed.

## Developing

To work on this project, you'll need `docker` and `make`. You may also want to have `lldb` for debugging.

To get started, clone the project to your development machine, then run one of the following commands within the project working directory:

- Run `make ready` to prepare a docker container that has everything needed for development activities. Do this before running any of the other following commands:

- Run `make test` to run the test suite.

- Run `make example` to compile and run from the sources in `./example`.

- Run `make example-lldb` to do the same as above, but run inside `lldb` to allow you to breakpoint and step through code.
