So now, knowing those type relationships, we can start to develop some best practices which will help people navigate which types of blocks/lambdas to use in their program architectures:

In general when designing code that accepts a block/lambda for use, you want to give maximum freedom to the calling code that is providing the block/lambda while still meeting your own needs for how you will use it.

With that in mind, here is a initial decision tree to use as an API design convention:

1. "I will only call the lambda immediately within the function that receives it"
  - if true: use `yield` and let the compiler infer the optimal underlying type based on yield sites, and let it have the best performance optimizations
  - if false: (continue to step 2)

2. "I can guarantee that I will only call this function once at most, and I want the lambda supplier to be able to use that guarantee to consume its captures (at the expense of requiring all captures to be sendable)"
  - if true: use `FunOnce` (a.k.a `FunOnce'iso`)
  - if false: (continue to step 3)

3. "This lambda will never need to be taken across an actor/region boundary (i.e. it doesn't need to be sendable)"
  - if true: (continue to step 4)
  - if false: (continue to step 5)

4. "The lambda will never need to be called from a read-only context (i.e. retrieving it from a field via a `box` viewpoint in order to call it)"
  - if true: use `Fun` (a.k.a `Fun'ref`)
  - if false: use `FunRead` (a.k.a `FunRead'box`)

5. "All of the arguments I need to pass into this lambda are sendable and the result I get out from it can also be sendable"
  - if true: use `Fun'iso`
  - if false: use `FunRead'val`

---

Or, as a more brief summary:

- use `yield` when there is no need to turn the lambda into an object
- accept `FunOnce` when there is no need to call it multiple times
- accept `Fun` or `FunRead` when there is no need to be sendable, preferring the former where the type system allows it
- otherwise accept `Fun'iso` or `FunRead'val`, preferring the former where the type system allows it
