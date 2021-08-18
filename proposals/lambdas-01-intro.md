Yield blocks use a syntax of `->` to attach the yield block to a call site. Async yield blocks will use a similar syntax of `...->`, creating what is effectively a lambda as known in other languages.

The primary reason for different syntax between the two types of yield blocks isn't to aid the compiler, but rather to aid the human reader in quickly understanding that when they see a `...->` they will know that the effects inside the block will take place at some time later, whereas the `->` will continue to represent a block will execute immediately zero or more times within the call site. Here the added `...` implies "some time later".

Like a `->` block, a `...->` block can capture variables, but unlike a `->` block, it cannot rebind the variables in ways that affect the outer scope (in part because the block happens later, and in part because that would break ref cap guarantees). The captured variables of a `...->` block get quietly lifted into fields of an underlying heap-allocated runtime object which represents the block (whereas in a `->` block the code is executing in the immediate context against the same local variables on the stack).

As you may expect, a `...->` block is also not allowed to return early or raise an error into the outer context (because it is executing at a later time, when the outer context is already complete).

The target of a `...->` call will often be a behavior (rather than a synchronous method), and that behavior will usually declare `:yields async` and/or have at least one `yield async` statement inside of it. Alternatively it is possible to objectify the `...->` block as a lambda object that could be stored in a field and called later, but the syntax for that isn't designed yet, and it's better to avoid that pattern unless/until it is necessary (it will probably be necessary for things like `Future` - see more notes later below).

With that said, let's look at an example below, which demonstrates a usage of the "access pattern" which [I have previously catalogued for Pony](https://patterns.ponylang.io/async/access.html). In Savi we will have a standard library trait called `Accessible` which canonicalizes the name `access` as a common convention (see more notes later below).

```savi
increase_amount U64 = 5

counter.access ...-> (counter |
  counter.value += increase_amount
  if (counter.value > 100) (
    @counter_did_finish(counter, counter.value)
  )
)
```

Notice also that the inner `counter` yield parameter (of type `Counter'ref`, as seen from inside the counter actor) shadows the outer `counter` local variable (of type `Counter'tag`, as seen from outside the counter actor).

Note also that the `increase_amount` variable from the outer scope is captured into the block, which uses it when called later. More subtly, the `@` is also captured from the outer scope as a `tag` reference (this is only allowed when the `@` is an actor), and the `counter_did_finish` behavior is called on that actor as a kind of callback.
