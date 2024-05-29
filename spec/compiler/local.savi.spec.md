---
pass: local
---

It marks the use sites of local variables.

```savi
  res_1 = (x = "value")       ::local.use_site=> x:W:(0, 5)
  res_2 = (x <<= "new value") ::local.use_site=> x:RW:(0, 13)
  try (
    res_3 = x                 ::local.use_site=> x:R:(3, 18)
    res_4 = (--x)             ::local.use_site=> x:C:(3, 24)
  )
```

---

It marks the use sites of the local-like "self" variable (@).

```savi
  :fun iso call
    @            ::local.use_site=> @:R:(0, 0)
    result = (--@) ::local.use_site=> @:C:(0, 5)
    --result
```

---

It marks the use sites of parameters.

```savi
  :fun call(
    arg_1                  ::local.use_site=> arg_1:W:(0, 0)
    arg_2 String           // can't easily annotate here unfortunately
    arg_3 String = "value" // can't easily annotate here unfortunately
  )
    try (
      res_3 = arg_1        ::local.use_site=> arg_1:R:(3, 15)
      res_4 = (--arg_2)    ::local.use_site=> arg_2:C:(3, 21)
    )
    (arg_3 = "new value")  ::local.use_site=> arg_3:W:(2, 31)
```

---

It marks the use sites of yield parameters.

```savi
  @yielding_call -> (
    arg_1                 ::local.use_site=> arg_1:W:(3, 2)
    arg_2                 ::local.use_site=> arg_2:W:(3, 3)
    arg_3                 ::local.use_site=> arg_3:W:(3, 4)
  |
    try (
      res_3 = arg_1       ::local.use_site=> arg_1:R:(6, 8)
      res_4 = (--arg_2)   ::local.use_site=> arg_2:C:(6, 14)
    )
    (arg_3 = "new value") ::local.use_site=> arg_3:W:(5, 24)
  )
```

---

It marks the use sites of a try catch expression variable.

```savi
  try (
    error! "value"
  |
    err          ::local.use_site=> err:W:(4, 4)
  |
    string = err ::local.use_site=> err:R:(5, 7)
  )
```

---

It complains when trying to read a local variable prior to its first assignment.

```savi
  x
  x = "value"
```
```error
This local variable has no assigned value yet:
  x
  ^
```

---

It complains differently for an identifier for which there is no solid proof that it is a local variable at all.

```savi
  bogus
```
```error
The identifier 'bogus' hasn't been defined yet:
  bogus
  ^~~~~
```

---

It complains differently for an identifier which exists as a member of the self type.

```savi
  my_field
  :let my_field: "example"
```
```error
A local variable with this name hasn't been defined yet:
  my_field
  ^~~~~~~~

- if you want to access this member, prefix the identifier with the `@` symbol:
  :let my_field: "example"
       ^~~~~~~~
```

---

It complains when trying to read a local variable without guarantee of assignment.

```savi
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

It complains when trying to read a local variable after a preceding consume.

```savi
  x = "value"
  case (
  | @cond_1 | @send(--x)
  | @cond_2 | @send(--x)
  | @cond_3 | @send("some other value")
  )
  @show(x)
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

---

It complains when trying to consume a local variable after a preceding consume.

```savi
  x = "value"
  case (
  | @cond_1 | @send(--x)
  | @cond_2 | @send(--x)
  | @cond_3 | @send("some other value")
  )
  @send(--x)
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

```savi
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

```savi
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

```savi
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

```savi
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

```savi
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

```savi
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

```savi
  x = "value"
  while True (x | --x)
```

---

It unconsumes a variable if assigned from an expression that consumes it:

```savi
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
