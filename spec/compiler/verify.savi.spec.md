---
pass: verify
---

The verify pass will complain if we have no Main actor defined, so we define one for this test file:

```savi
:actor Main
  :new (env Env)
    None
```

---

It complains when an actor constructor has an error-able body:

```savi
:actor ActorWithErrorableConstructor
  :new
    error!
```
```error
This actor constructor may raise an error, but that is not allowed:
  :new
   ^~~

- an error may be raised here:
    error!
    ^~~~~~
```

---

It complains when a no-exclamation function has an error-able body:

```savi
  :fun risky(x U64)
    if (x == 0) (error!)
```
```error
This function name needs an exclamation point because it may raise an error:
  :fun risky(x U64)
       ^~~~~

- it should be named 'risky!' instead:
  :fun risky(x U64)
       ^~~~~

- an error may be raised here:
    if (x == 0) (error!)
                 ^~~~~~
```

---

It complains when a try body has no possible errors to catch:

```savi
    try (U64[33] * 3)
```
```error
This try block is unnecessary:
    try (U64[33] * 3)
    ^~~

- the body has no possible error cases to catch:
    try (U64[33] * 3)
        ^~~~~~~~~~~~~
```

---

It complains if trying to take the stack address of a non-variable:

```savi
    foo = 99
    stack_address_of_variable foo
    stack_address_of_variable String
```
```error
This is not a local variable, so it has no stack address:
    stack_address_of_variable String
                              ^~~~~~
```

---

It complains when an async function declares or tries to yield:

```savi
:actor ActorWithYieldingBehavior
  :be try_to_yield
    :yields Bool
    yield True
    yield False
```
```error
An asynchronous function cannot yield values:
  :be try_to_yield
      ^~~~~~~~~~~~

- it declares a yield here:
    :yields Bool
            ^~~~

- it yields here:
    yield True
    ^~~~~

- it yields here:
    yield False
    ^~~~~
```

---

It complains when a constructor declares or tries to yield:

```savi
  :new try_to_yield
    :yields Bool
    yield True
    yield False
```
```error
A constructor cannot yield values:
  :new try_to_yield
       ^~~~~~~~~~~~

- it declares a yield here:
    :yields Bool
            ^~~~

- it yields here:
    yield True
    ^~~~~

- it yields here:
    yield False
    ^~~~~
```
