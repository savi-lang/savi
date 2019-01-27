# Mare

<img alt="The ungui-angui-pede, a mascot for Mare" src="https://openclipart.org/download/191499/1393759624.svg" width="100px" />

Mare is a reimagining of the [Pony](https://www.ponylang.io/) language.

The goal is to create a language with all the desirable features of Pony, while simultaneously being more approachable to newcomers and more extensible for power users.

It's an early work in progress, but it can already compile and run basic programs.

## Developing

To work on this project, you'll need `docker` and `make`. Clone the project to your development machine, then run one of the following commands:

- Run `make ready` to prepare a docker container that has everything needed for development activities. Do this before running any of the other following commands:

- Run `make test` to run the test suite.

## Roadmap

### Features from Pony (and other basic language features)

- [x] - FFI function calling
- [x] - Stateless, non-allocated primitives with pure functions
- [x] - Numeric machine word types
- [x] - Stateful, allocated classes with constructors and methods
- [x] - Properties (fields hidden behind getters/setters)
- [x] - Interfaces
- [ ] - Virtual table calls on abstract types
- [ ] - Boxed numeric values
- [ ] - Non-looping flow control (`if`, `match`, etc)
- [ ] - Looping flow control (`while`, etc)
- [ ] - Reference capabilities (`iso`, `trn`, `val`, `ref`, `box`, `tag`)
- [ ] - Actors and behaviours
- [ ] - For-loop iterator syntax sugar (`for x in y`)
- [ ] - Generic types
- [ ] - FFI-compatible struct types

### New features (that were *NOT* in Pony)

- [x] - Compile-time constant values
- [x] - User-defined custom numeric types (`numeric MyNumber:`)
- [ ] - Enumerated custom numeric types (`enum MyEnum:`)
- [ ] - Non-allocated class references with "static" stateless functions.
- [ ] - Typeclasses (`implement SomeInterface for SomeClass:`)
- [ ] - Automatic specialization of functions to avoid virtual table calls.

### New sugar and other conveniences

- [x] - More type inference (return types, parameter types, etc)
- [x] - Self-value syntax sugar (`@`, `@method(args)`, etc)
- [x] - Setter syntax sugar (`obj.prop = value` calls the `prop=` method)
- [x] - Parameter assign expression syntax sugar (`new (@propa, @propb)`)

### Tooling features

- [ ] - Docker image of the Mare compiler
- [ ] - Distributable package for Linux with Mare compiler static binary
- [ ] - Sublime Text syntax highlighting support
- [ ] - Language Server Protocol support
- [ ] - Doctests support
- [ ] - Dependency manager / package manager

## Goals and Non-Goals

### Goals

- Use the same runtime as Pony.
    - Mare uses `libponyrt`, the same high-performance runtime that runs Pony.

- Include all desirable language features from Pony.
    - If it's possible to write a given program in Pony, it should be possible to write the same program in Mare, using the same (or better) design patterns and yielding equivalent (or better) runtime performance.

- Co-maximize readability and succinctness.
    - There are times when readability conflicts with succinctness (and in such cases one should always prefer readability), but more often succinctness concerns are aligned with readability. Truly readable code is code that clearly displays the intent of the author - no more and no less. The syntax of the language should allow authors to walk the narrow path between conveying a meaning that is obscured behind terse occult symbols and conveying a meaning that is drowned in a sea of verbose boilerplate.

- Compiler architecture that maximizes ease of extensibility.
    - Tweaking and customizing syntax (a category of features often called metaprogramming) should be encouraged and facilitated.
    - Each piece of logic in the compiler should be decoupled from as many implicit assumptions as possible. Special cases should be avoided wherever possible in favor of forms that third-party code can reproduce on its own.
    - The compiler should be written in a language (for now, Crystal) that also co-maximizes readability and succinctness as defined above, so that it is a joy to maintain.

- Tooling is paramount.
    - Developer experience is governed not only by language features, but also by tooling. To provide an attractive developer experience, Mare needs excellent tooling support.

### Non-Goals

- A comprehensive standard library that contains everything you need.
    - The standard library should be a stable, minimal set of tools that change slowly and deliberately, doing no more than they need to. The package ecosystem outside the standard library is the place for rapid and diverse innovation.

- A homogenous culture of mechanical code formatting.
    - Code is an art form, and the manner in which you as an author choose to express yourself is important. There are many "bad" (hard to read) ways to format your code, but there are also many "good" (easy to read) ways to format your code, and it is your responsibility to find the "best" (most readable) way, which may often depend on context too subtle for a mechanical formatter to understand.
