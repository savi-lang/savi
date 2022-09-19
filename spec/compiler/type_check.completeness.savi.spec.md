---
pass: type_check
---

It complains when access to the self is shared while still incomplete:

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
```error
The type of this expression doesn't meet the constraints imposed on it:
    AccessWhileIncomplete.data(@)
                               ^

- it is required here to be a subtype of Any'box:
  :fun data(any Any'box)
                ^~~~~~~

- but the type of the receiver value was ItComplainsWhenAccessToTheSelfIsSharedWhileStillIncomplete0'tag:
    AccessWhileIncomplete.data(@)
                               ^

- this can be reached while in an incomplete constructor (that is, before all fields are initialized) so it's not safe to share publicly here:
    AccessWhileIncomplete.data(@)
                               ^

- it can be reached from this constructor:
  :new ref
   ^~~
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
