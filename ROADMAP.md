### Features from Pony (and other basic language features)

- [x] - FFI function calling
- [x] - Stateless, non-allocated modules with pure functions
- [x] - Numeric machine word types
- [x] - Stateful, allocated classes with constructors and methods
- [x] - Properties (fields hidden behind getters/setters)
- [x] - Traits (for structural subtyping and/or code reuse)
- [x] - Virtual table calls on abstract types
- [x] - Non-looping flow control (`if`, `case`, etc)
- [x] - Runtime type matching (`x <: Y`)
- [x] - Boxed numeric values
- [x] - Actors and behaviours
- [x] - Rcaps (`iso`, `val`, `ref`, `box`, `tag`) (`trn` was removed)
- [x] - Rcap ephemerality (alias rcaps, ephemeral rcaps, `consume`)
- [x] - Automatic receiver recovery for ephemeral receivers
- [x] - Rcap viewpoint adaptation
- [x] - Generic types and generic rcaps
- [x] - Array literals
- [x] - Looping flow control (`while`)
- [x] - Partial functions and partial calls
- [x] - ~For-loop iterator syntax sugar (`for x in y`)~ (replaced by the new feature known as yielding functions)
- [ ] - Rcaps manual recovering (`recover` block)
- [ ] - Tuple values
- [ ] - Finalizer functions
- [ ] - FFI-compatible struct types

### New features (that were *NOT* in Pony)

- [x] - Compile-time constant values
- [x] - User-defined custom numeric types (`numeric MyNumber:`)
- [x] - Enumerated custom numeric types (`enum MyEnum:`)
- [x] - Non-allocated class references with "static" stateless functions.
- [ ] - Yielding functions as a cleaner alternative to Iterators, for-loops, and immediately-used lambdas
- [ ] - Doctests
- [ ] - Command Line REPL
- [ ] - Typed errors and debug-mode error state with no release-mode overhead.
- [ ] - Typeclasses (`implement SomeTrait for SomeClass:`)
- [ ] - Automatic specialization of functions to avoid virtual table calls.
- [ ] - Sourcing/overriding constant values using compile-time options
- [ ] - Builtin/automatic support for Pony's "Access Pattern"

### New sugar and other conveniences

- [x] - More type inference (return types, parameter types, etc)
- [x] - Self-value syntax sugar (`@`, `@method(args)`, etc)
- [x] - Setter syntax sugar (`obj.prop = value` calls the `prop=` method)
- [x] - Parameter assign expression syntax sugar (`new (@propa, @propb)`)

### Tooling features

- [x] - Emit debugging metadata in compiled programs
- [ ] - Docker image of the Savi compiler
- [ ] - Distributable package for Linux with Savi compiler static binary
- [ ] - Sublime Text syntax highlighting support
- [ ] - Language Server Protocol support
- [ ] - Doctests support
- [ ] - Dependency manager / package manager

# Miscellaneous Tasks

- [ ] - Audit for entity name collision issues and restrict as necessary
