---
pass: t_type_check
---

TODO: It complains when access to the self is shared while still incomplete:

```savi
    @x = 1
    AccessWhileIncomplete.data(@)
    @y = 2
    @z = 3

  :var x U64
  :var y U64
  :var z U64

:module AccessWhileIncomplete
  :fun data(any Any'box)
    any
```

---

It allows opaque sharing of the self while still incomplete and non-opaque sharing of the self after becoming complete:

```savi
    @x = 1
    TouchWhileIncomplete.data(@)
    @y = 2
    @z = 3
    AccessAfterComplete.data(@)

  :var x U64
  :var y U64
  :var z U64

:module AccessAfterComplete
  :fun data(any Any'box)
    any

:module TouchWhileIncomplete
  :fun data(any Any'tag)
    any
```
