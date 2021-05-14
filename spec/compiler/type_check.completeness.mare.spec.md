---
pass: type_check
---

It complains when access to the self is shared while still incomplete:

```mare
    @x = 1
    AccessWhileIncomplete.data(@)
    @y = 2
    @z = 3

  :prop x U64
  :prop y U64
  :prop z U64

:primitive AccessWhileIncomplete
  :fun data(any Any'box)
    any
```
```error
This usage of `@` shares field access to the object from a constructor before all fields are initialized:
    AccessWhileIncomplete.data(@)
                               ^

- if this constraint were specified as `tag` or lower it would not grant field access:
  :fun data(any Any'box)
                ^~~~~~~

- this field didn't get initialized:
  :prop y U64
        ^

- this field didn't get initialized:
  :prop z U64
        ^
```

---

It allows opaque sharing of the self while still incomplete and non-opaque sharing of the self after becoming complete:

```mare
    @x = 1
    TouchWhileIncomplete.data(@)
    @y = 2
    @z = 3
    AccessAfterComplete.data(@)

  :prop x U64
  :prop y U64
  :prop z U64

:primitive AccessAfterComplete
  :fun data(any Any'box)
    any

:primitive TouchWhileIncomplete
  :fun data(any Any'tag)
    any
```
