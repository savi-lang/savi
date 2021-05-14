---
pass: consumes
---

It complains when an already-consumed local is referenced:

```mare
    x = "example"
    --x
    x
```
```error
This variable can't be used here; it might already be consumed:
    x
    ^

- it was consumed here:
    --x
    ^~~
```

---

It complains when a possibly-consumed local is referenced:

```mare
    x = "example"
    if True (--x)
    x
```
```error
This variable can't be used here; it might already be consumed:
    x
    ^

- it was consumed here:
    if True (--x)
             ^~~
```

---

It complains when an already-consumed @ is referenced:

```mare
  :fun iso call
    result = --@
    @.call
    result
```
```error
This variable can't be used here; it might already be consumed:
    @.call
    ^

- it was consumed here:
    result = --@
             ^~~
```

---

It complains when referencing a possibly-consumed local from a choice:

```mare
  :fun show(u U64)
    if (u <= 3) (
      case (
      | u == 1 | x = "one" // no consume
      | u == 2 | x = "two",   --x
      | u == 2 | x = "three", --x
      |          x = "four",  --x
      )
    |
      x = "four", --x
    )
    x
```
```error
This variable can't be used here; it might already be consumed:
    x
    ^

- it was consumed here:
      | u == 2 | x = "two",   --x
                              ^~~

- it was consumed here:
      | u == 2 | x = "three", --x
                              ^~~

- it was consumed here:
      |          x = "four",  --x
                              ^~~

- it was consumed here:
      x = "four", --x
                  ^~~
```

---

It allows referencing a local consumed in an earlier choice branch:

```mare
  :fun show(u U64)
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
  :fun show(u U64)
    if (--u == 1) (
      "one"
    |
      u
    )
```
```error
This variable can't be used here; it might already be consumed:
      u
      ^

- it was consumed here:
    if (--u == 1) (
        ^~~
```

---

It complains when a choice cond uses a local consumed before the choice:

```mare
  :fun show(u U64)
    --u
    if (u == 1) ("one" | "other")
```
```error
This variable can't be used here; it might already be consumed:
    if (u == 1) ("one" | "other")
        ^

- it was consumed here:
    --u
    ^~~
```

---

It complains when consuming a local in a loop cond:

```mare
    x = "example"
    while --x (True)
```
```error
This variable can't be used here; it might already be consumed:
    while --x (True)
            ^

- it was consumed here:
    while --x (True)
          ^~~
```

---

It complains when consuming a local in a loop body:

```mare
    x = "example"
    while True (--x)
```
```error
This variable can't be used here; it might already be consumed:
    while True (--x)
                  ^

- it was consumed here:
    while True (--x)
                ^~~
```

---

It complains when using a local possibly consumed in a loop else body:

```mare
    x = "example"
    while True (None | --x)
    x
```
```error
This variable can't be used here; it might already be consumed:
    x
    ^

- it was consumed here:
    while True (None | --x)
                       ^~~
```

---

It allows referencing a local in the body of a loop consumed in the else:

```mare
    x = "example"
    while True (x | --x)
```

---

It complains when a loop cond uses a local consumed before the loop:

```mare
  :fun show(u U64)
    --u
    while (u == 1) ("one" | "other")
```
```error
This variable can't be used here; it might already be consumed:
    while (u == 1) ("one" | "other")
           ^

- it was consumed here:
    --u
    ^~~
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

  :fun non indirect(s String'iso) String'iso: --s
  :fun non indirect_partial!(s String'iso) String'iso: --s
```
```error
This variable can't be used here; it might already be consumed:
    x // NOT OKAY; reassignment is partial
    ^

- it was consumed here:
    try (x = @indirect_partial!(--x))
                                ^~~
```
