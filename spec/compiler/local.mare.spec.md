---
pass: local
---

It marks the use sites of local variables.

```mare
  res_1 = (x = "value")       ::local.use_site=> x:W:(0, 5)
  res_2 = (x <<= "new value") ::local.use_site=> x:RW:(0, 13)
  try (
    res_3 = x                 ::local.use_site=> x:R:(3, 18)
    res_4 = --x               ::local.use_site=> x:C:(3, 24)
  )
```

---

It marks the use sites of the local-like "self" variable (@).

```mare
  :fun iso call
    @            ::local.use_site=> @:R:(0, 0)
    result = --@ ::local.use_site=> @:C:(0, 5)
    --result
```

---

It marks the use sites of parameters.

```mare
  :fun call(
    arg_1                  ::local.use_site=> arg_1:W:(0, 0)
    arg_2 String           // can't easily annotate here unfortunately
    arg_3 String = "value" // can't easily annotate here unfortunately
  )
    try (
      res_3 = arg_1   ::local.use_site=> arg_1:R:(3, 13)
      res_4 = --arg_2 ::local.use_site=> arg_2:C:(3, 19)
    )
    (arg_3 = "new value") ::local.use_site=> arg_3:W:(2, 28)
```

---

It marks the use sites of yield parameters.

```mare
  @yielding_call -> (
    arg_1                  ::local.use_site=> arg_1:W:(3, 1)
    arg_2 String           // can't easily annotate here unfortunately
    arg_3 String = "value" // can't easily annotate here unfortunately
  |
    try (
      res_3 = arg_1   ::local.use_site=> arg_1:R:(6, 14)
      res_4 = --arg_2 ::local.use_site=> arg_2:C:(6, 20)
    )
    (arg_3 = "new value") ::local.use_site=> arg_3:W:(5, 29)
  )
```

---

It complains when trying to read a local variable prior to its first assignment.

```mare
  x // NOT OKAY - prior to any assignment

  case (
  | @cond_1 | x = "one"
  | @cond_2 | x = "two"
  )
  x // NOT OKAY - not guaranteed to be assigned

  case (
  | @cond_3 | x = "three"
  | @cond_4 | x = "four"
  | x = "other"
  )
  x // okay - it was guaranteed to be assigned in one of the branches
```
```error
This local variable has no assigned value yet:
  x // NOT OKAY - prior to any assignment
  ^
```
```error
This local variable isn't guaranteed to have a value yet:
  x // NOT OKAY - not guaranteed to be assigned
  ^

- this assignment is not guaranteed to precede that usage:
  | @cond_1 | x = "one"
              ^

- this assignment is not guaranteed to precede that usage:
  | @cond_2 | x = "two"
              ^
```

---

It complains when trying to read or consume a local variable after a preceding consume.

```mare
  x = "value"
  case (
  | @cond_1 | @send(--x)
  | @cond_2 | @send(--x)
  | @cond_3 | @send("some other value")
  )
  @show(x)
  @send(--x)
```
```error
This local variable has no value anymore:
  @show(x)
        ^

- it is consumed in a preceding place here:
  | @cond_1 | @send(--x)
                      ^

- it is consumed in a preceding place here:
  | @cond_2 | @send(--x)
                      ^
```
```error
This local variable can't be consumed again:
  @send(--x)
          ^

- it is consumed in a preceding place here:
  | @cond_1 | @send(--x)
                      ^

- it is consumed in a preceding place here:
  | @cond_2 | @send(--x)
                      ^
```

---

It allows reading or consuming a preceding consume-and-write.

```mare
  x = "value"
  case (
  | @cond_1 | @send(--x), x = "new value"
  | @cond_2 | @send(--x), x = "new value"
  | @cond_3 | @send("some other value")
  )
  @show(x)
  @send(--x)
```

---

It allows referencing a local consumed in an earlier choice branch:

```mare
  u USize = 0
  case (
  | u == 1 | --u, x = "one"
  | u == 2 | --u, x = "two"
  | u == 2 | --u, x = "three"
  |          --u, x = "four"
  )
```

---

It complains when a choice body uses a local consumed in an earlier cond:

```mare
  u USize = 0
  if (--u == 1) (
    "one"
  |
    u
  )
```
```error
This local variable has no value anymore:
    u
    ^

- it is consumed in a preceding place here:
  if (--u == 1) (
        ^
```

---

It complains when consuming a local in a loop cond:

```mare
  x = "value"
  while --x (True)
```
```error
This local variable can't be consumed again:
  while --x (True)
          ^

- it is consumed in a preceding place here:
  while --x (True)
          ^
```

---

It complains when consuming a local in a loop body:

```mare
  x = "value"
  while True (--x)
```
```error
This local variable can't be consumed again:
  while True (--x)
                ^

- it is consumed in a preceding place here:
  while True (--x)
                ^
```

---

It complains when using a local possibly consumed in a loop else body:

```mare
  x = "value"
  while True (None | --x)
  x
```
```error
This local variable has no value anymore:
  x
  ^

- it is consumed in a preceding place here:
  while True (None | --x)
                       ^
```

---

It allows referencing a local in the body of a loop consumed in the else:

```mare
  x = "value"
  while True (x | --x)
```

---

It unconsumes a variable if assigned from an expression that consumes it:

```mare
  x = String.new_iso
  x = @indirect(--x)
  x // okay; unconsumed
  if True (x = @indirect(--x))
  x // okay; unconsumed
  i U8 = 0, while (i < 5) (i += 1, x = @indirect(--x))
  x // okay; unconsumed
  try (x = @indirect(--x), error!)
  x // okay; unconsumed
  try (x = @indirect_partial!(--x))
  x // NOT OKAY; reassignment is partial
```
```error
This local variable has no value anymore:
  x // NOT OKAY; reassignment is partial
  ^

- it is consumed in a preceding place here:
  try (x = @indirect_partial!(--x))
                                ^
```
