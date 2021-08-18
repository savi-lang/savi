So now, knowing those type relationships, we can start to develop some best practices which will help people navigate which types of blocks/lambdas to use in their program architectures:

In general when designing code that accepts a block/lambda for use, you want to give maximum freedom to the calling code that is providing the block/lambda while still meeting your own needs for how you will use it.

With that in mind, here is a initial decision tree to use as an API design convention:

1. "I will only call the lambda immediately within the function that receives it"
  - if true: use `yield` and let the compiler infer the optimal underlying type based on yield sites, and let it have the best performance optimizations
  - if false: (continue below)

2. "I can guarantee that I will only call this function once at most"
  - if true: use `FunOnce` (a.k.a `FunOnce'iso`)
  - if false: (continue below)

3. "This lambda will never need to be taken across an actor/region boundary (i.e. it doesn't need to be sendable)"
  - if true: use `Fun` (a.k.a `Fun'ref`)
  - if false: (continue below)

4. "All of the arguments I need to pass into this lambda are sendable and the result I get out from it can also be sendable"
  - if true: use `Fun'iso`
  - if false: use `FunVal` (a.k.a `FunVal'val`)
