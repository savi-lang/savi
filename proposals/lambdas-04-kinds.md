Now let's talk about the different kinds of blocks/lambdas that seem possible and useful, what restrictions they have, and how they will be implemented under the hood.

After that we can talk about how they fit into the type system and language together.

## Kind A (immediate yield block)

Call count:
  - can be called zero or more times

Inter-scope interaction:
  - can capture variables from the outer scope
  - can rebind captured variables, affecting the outer scope
  - CANNOT consume captured variables in the inner scope (unless they are guaranteed to get rebound later in the same code path) - this is just like the rules for a loop body
  - can raise an error into the outer scope
  - can return early, exiting the outer scope

Ref cap restrictions:
  - can capture non-sendable values from the outer scope
  - can receive non-sendable yielded values
  - can return a non-sendable yield result value

Mobility:
  - CANNOT cross an actor boundary
  - CANNOT be objectified or stored away for later (yields must occur in the immediate scope of the called function)

Theoretical "as if" modeling:
  - It's as if the called function state were kept on the stack to pause and continue execution across multiple intermediate returns

Internal Implementation / Optimization:
  - the block has no reference capability to track, as it is not objectified
  - zero or more calls with intermediate return values representing yields from the called function
  - stack-allocated "continuation struct" persists stack state for called function across multiple calls
  - for a self-recursive yielding function, the continuation struct must be heap-allocated instead of stack-allocated, but the rest of the semantics are not affected.

## Kind B (single-use isolated lambda)

Call count:
  - can be called zero or one time
  - CANNOT be called more than once

Inter-scope interaction:
  - can capture variables from the outer scope
  - can rebind captured variables in the inner scope (but not the outer scope)
  - can consume `iso` variables in the inner scope, provided that they aren't used any more in the outer scope (and thus the consume does not affect the outer scope)
  - CANNOT affect variable bindings in the outer scope
  - CANNOT raise an error into the outer scope
  - CANNOT return early, exiting the outer scope

Ref cap restrictions:
  - CANNOT capture non-sendable values from the outer scope
  - can receive non-sendable yielded values
  - can return a non-sendable yield result value

Mobility:
  - can cross an actor boundary
  - can be objectified and stored away for later, but only as an `iso` with `:fun iso` so as to be single-use

Theoretical "as if" modeling:
  - It's as if the block becomes an object (with ref cap: `iso`)
  - the object has a single function corresponding to the block body
  - the captured variables are arguments to a `:new iso` constructor
  - within the block, the captured variables are fields, which may be rebound internally
  - the block function is a `:fun iso` that immediately lowers itself to `ref`, so that the captured variable fields may be seen through the un-colored `ref` lens.
  - the `ref` is not recovered to an `iso`, so the function is not callable again

Internal Implementation / Optimization:
  - when objectified, it is a heap-allocated object of an anonymous one-off type, behaving like the "as if" model, and using a virtual table for dispatch when called.
  - in some cases, virtual dispatch on the object may be possible to avoid by using automatic specialization optimizations in the late compiler stages.
  - a second block that is tail-chained to it without accruing additional captures may be optimized to be another virtual method attached to the same runtime object
  - a second block that is tail-chained to it WITH additional captures accrued from the first block may get the same optimization if the first block is proved to be single-use (either by being an objectified single-use or a non-objectified definition with lexical proof of not being multi-use) - the additional captures become fields which are set during the execution of the first block and proven to be ready when they are used in the second block

## Kind C (multi-use isolated lambda)

Call count:
  - can be called zero or more times

Inter-scope interaction:
  - can capture variables from the outer scope
  - can rebind captured variables in the inner scope (but not the outer scope)
  - CANNOT consume `iso` variables in the inner scope
  - CANNOT affect variable bindings in the outer scope
  - CANNOT raise an error into the outer scope
  - CANNOT return early, exiting the outer scope

Ref cap restrictions:
  - CANNOT capture non-sendable values from the outer scope
  - CANNOT receive non-sendable yielded values
  - CANNOT return a non-sendable yield result value

Mobility:
  - can cross an actor boundary
  - can be objectified and stored away for later

Theoretical "as if" modeling:
  - It's as if the block becomes an object (with ref cap: `iso`)
  - the object has a single function corresponding to the block body
  - the captured variables are arguments to a `:new iso` constructor
  - within the block, the captured variables are fields, which may be rebound internally
  - the block function is a `:fun ref` with an auto-recovered receiver, meaning that nothing non-sendable may pass into or out of the block function (via its arguments or return value aka the yielded values or yield result value).

Internal Implementation / Optimization:
  - when objectified, it is a heap-allocated object of an anonymous one-off type, behaving like the "as if" model, and using a virtual table for dispatch when called.
  - in some cases, virtual dispatch on the object may be possible to avoid by using automatic specialization optimizations in the late compiler stages.
  - a second block that is tail-chained to it without accruing additional captures may be optimized to be another virtual method attached to the same runtime object
  - a second block that is tail-chained to it WITH additional captures accrued from the first block may get the same optimization if the first block is proved to be single-use (i.e. a non-objectified definition with lexical proof of not being multi-use) - the additional captures become fields which are set during the execution of the first block and proven to be ready when they are used in the second block

## Kind D (mutable lambda)

Call count:
  - can be called zero or more times

Inter-scope interaction:
  - can capture variables from the outer scope
  - can rebind captured variables in the inner scope (but not the outer scope)
  - CANNOT consume `iso` variables in the inner scope
  - CANNOT affect variable bindings in the outer scope
  - CANNOT raise an error into the outer scope
  - CANNOT return early, exiting the outer scope

Ref cap restrictions:
  - can capture non-sendable values from the outer scope
  - can receive non-sendable yielded values
  - can return a non-sendable yield result value

Mobility:
  - CANNOT cross an actor boundary
  - can be objectified and stored away for later (in fact that is the only valid use case for this variant)

Theoretical "as if" modeling:
  - It's as if the block becomes an object (with ref cap: `ref`)
  - the object has a single function corresponding to the block body
  - the captured variables are arguments to a `:new ref` constructor
  - within the block, the captured variables are fields, which are seen through the un-colored lens of `:fun ref`.

Internal Implementation / Optimization:
  - when objectified, it is a heap-allocated object of an anonymous one-off type, behaving like the "as if" model, and using a virtual table for dispatch when called.
  - in some cases, virtual dispatch on the object may be possible to avoid by using automatic specialization optimizations in the late compiler stages.
  - when non-objectified, single-use, another lambda that is tail-chained to it may be optimized to
  - when not objectified, it is possible to silently lift this to a Kind A implementation because it doesn't cross an actor boundary and a non-objectified yielding call can only do immediate yields; it's probably best in such a case to print a linting error instructing the code author to specify a Kind A yield block instead.

## Kind E (immutable lambda)

Call count:
  - can be called zero or more times

Inter-scope interaction:
  - can capture variables from the outer scope
  - CANNOT rebind captured variables in the inner scope
  - CANNOT consume `iso` variables in the inner scope
  - CANNOT affect variable bindings in the outer scope
  - CANNOT raise an error into the outer scope
  - CANNOT return early, exiting the outer scope

Ref cap restrictions:
  - CANNOT capture non-shareable values from the outer scope
  - can receive non-sendable yielded values
  - can return a non-sendable yield result value

Mobility:
  - can cross an actor boundary
  - can be objectified and stored away for later

Theoretical "as if" modeling:
  - It's as if the block becomes an object (with ref cap: `val`)
  - the object has a single function corresponding to the block body
  - the captured variables are arguments to a `:new val` constructor
  - within the block, the captured variables are fields, which may not be rebound because the block function is a `:fun box`.

Internal Implementation / Optimization:
  - when objectified, it is a heap-allocated object of an anonymous one-off type, behaving like the "as if" model, and using a virtual table for dispatch when called.
  - in some cases, virtual dispatch on the object may be possible to avoid by using automatic specialization optimizations in the late compiler stages.
  - a second block that is tail-chained to it without accruing additional captures may be optimized to be another virtual method attached to the same runtime object
  - a second block that is tail-chained to it WITH additional captures accrued from the first block may get the same optimization if the first block is proved to be single-use (i.e. a non-objectified definition with lexical proof of not being multi-use) - the additional captures become fields which are set during the execution of the first block and proven to be ready when they are used in the second block

## Kind F (read-only lambda)

Call count:
  - can be called zero or more times

Inter-scope interaction:
  - can capture variables from the outer scope
  - CANNOT rebind captured variables in the inner scope
  - CANNOT consume `iso` variables in the inner scope
  - CANNOT affect variable bindings in the outer scope
  - CANNOT raise an error into the outer scope
  - CANNOT return early, exiting the outer scope

Ref cap restrictions:
  - can capture non-shareable values from the outer scope
  - HOWEVER, all captured values are seen through a `box` lens - no mutation of them is possible
  - can receive non-sendable yielded values
  - can return a non-sendable yield result value

Mobility:
  - can cross an actor boundary
  - can be objectified and stored away for later

Theoretical "as if" modeling:
  - It's as if the block becomes an object (with ref cap: `box`)
  - the object has a single function corresponding to the block body
  - the captured variables are arguments to a `:new box` constructor
  - within the block, the captured variables are fields, which may not be rebound because the block function is a `:fun box`.

Internal Implementation / Optimization:
  - when objectified, it is a heap-allocated object of an anonymous one-off type, behaving like the "as if" model, and using a virtual table for dispatch when called.
  - in some cases, virtual dispatch on the object may be possible to avoid by using automatic specialization optimizations in the late compiler stages.
  - a second block that is tail-chained to it without accruing additional captures may be optimized to be another virtual method attached to the same runtime object
  - a second block that is tail-chained to it WITH additional captures accrued from the first block may get the same optimization if the first block is proved to be single-use (i.e. a non-objectified definition with lexical proof of not being multi-use) - the additional captures become fields which are set during the execution of the first block and proven to be ready when they are used in the second block

## Kind G ("pure" lambda)

Call count:
  - can be called zero or more times

Inter-scope interaction:
  - CANNOT capture variables from the outer scope
  - CANNOT rebind captured variables in the inner scope
  - CANNOT consume `iso` variables in the inner scope
  - CANNOT affect variable bindings in the outer scope
  - CANNOT raise an error into the outer scope
  - CANNOT return early, exiting the outer scope

Ref cap restrictions:
  - can receive non-sendable yielded values
  - can return a non-sendable yield result value

Mobility:
  - can cross an actor boundary
  - can be objectified and stored away for later

Theoretical "as if" modeling:
  - It's as if the block becomes a function on a `:module` (with ref cap: `non`)
  - the function is a `:fun non`
  - Note that in Savi's type system a `:module` type can adhere to function traits of any receiver cap because there are no fields to track - so it is possible for example to adhere to a trait with a `:fun iso`, `:fun ref`, or `:fun val` even though the function declared on the module is a `:fun non`.

Internal Implementation / Optimization:
  - when objectified, it is a static-memory object of an anonymous one-off type, behaving like the "as if" model, and using a virtual table for dispatch when called.
  - in some cases, virtual dispatch on the object may be possible to avoid by using automatic specialization optimizations in the late compiler stages.
