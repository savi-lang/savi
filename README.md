<img alt="Savi Logo" src="./assets/savi-logo-rect.png" width="454px" />

---

**Savi** is a **fast** language for programmers
  who are **passionate about their craft**.

---

**Savi** will **change the way you think** about programming
  and equip you with the skills and tools you need
    to tackle **more ambitious** technical challenges,
    and **have fun** doing it.

---

**Savi** is here to help you write blazing-fast,
  **concurrent** software that is **memory-safe** and **data-race-free**.

---

## Background

**Savi** is an actor-oriented programming language using the [Pony](https://www.ponylang.io/) runtime. Like Pony, **Savi** has a unique type system that enforces concurrency-safety and memory-safery properties at compile time.

Like many other modern compiled languages, **Savi** uses [LLVM](https://llvm.org/) to compile to a wide variety of native targets.

Our goal is to make **Savi** approachable and fun, as well as powerful and extensible.

We are a small team of passionate volunteers working to bring this project to full fruition. If this vision sounds interesting to you, we'd love for you to [reach out in our chat](https://savi.zulipchat.com/) and get involved.

## Try It!

[![Docker](https://img.shields.io/docker/cloud/automated/jemc/savi.svg)](https://hub.docker.com/r/jemc/savi)

There are a few ways you can try out Savi. All of them assume you have a working `docker` installation, so take a moment to take care of that first.

First, just to prove the basics, you can use the `eval` subcommand of the docker image to compile a program:

```sh
docker run --rm jemc/savi eval 'env.out.print("Hello, World!")'
# Prints "Hello, World!"
```

Beyond that, you can also use the docker image to compile a source code directory by mounting the directory into the container, like so:

```sh
# Compile the program.
docker run --rm -v ${PATH_TO_YOUR_CODE}:/opt/code jemc/savi
# Run the program.
${PATH_TO_YOUR_CODE}/main
```

If you're a VS Code user, you may be interested to install our [language extension for that editor](./tooling/vscode), which includes both syntax highlighting and some Intellisense features via using the docker image as an LSP server.

We also have [a vim/nvim extension](./tooling/coc-nvim) as well.

Finally, if you want to contribute to Savi, read on through the next two sections for information on how to find work, as well some of the basic development commands.

## Contributing

Looking for ways to help? [Here's a link that shows issue tickets filtered by those that should be ready to work on](https://github.com/savi-lang/savi/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc+-label%3ABLOCKED+-label%3A%22complexity+4%3A+scary%22+-label%3A%22needs+design%22).

You can also filter by complexity label to try to find something that's the right level of challenge and time commitment for you.

If you're a new contributor looking for some guidance, please reach out to us [in this chat room](https://savi.zulipchat.com/) to introduce yourself and even schedule pairing sessions where we can help you understand parts of the compiler or language that you're interested in learning more about.

We think you'll find it exciting to join us at this stage of our work, where there is already enough working that you can get things done and produce a tangible result, but it's early enough that you can have a strong impact on the future of the language and the community.

We are excited to welcome all contributors that bring a positive attitude, regardless of their level of experience. [Join us!](https://savi.zulipchat.com/)

## Developing

To work on this project, you'll need `docker` and `make`. You may also want to have `lldb` for debugging.

To get started, clone the project to your development machine, then run one of the following commands within the project working directory:

- Run `make ready` to prepare a docker container that has everything needed for development activities. Do this before running any of the other following commands:

- Run `make test` to run the test suite.

- Run `make example-run dir="/opt/code/examples/adventofcode/2018` to compile and run from the sources in `./examples/adventofcode/2018` directory (or similarly for any other example code directory).

- Run `make example-lldb` to do the same as above, but run inside `lldb` to allow you to breakpoint and step through code.
