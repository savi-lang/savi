---
pass: type_check
---

This type will be used throughout the following examples to demonstrate calling with yield blocks:

```mare
:primitive Numbers
  :fun will_not_yield: None

  :fun yield_99
    yield U64[99]

  :fun count_to(count U64) None
    :yields U64 for None
    i U64 = 0
    while (i < count) (
      i = i + 1
      yield i
    )
```

---

It yields values to the caller:

```mare
    sum U64 = 0
    Numbers.count_to(5) -> (i| sum = sum + i)
```

---

It complains when a yield block is present on a non-yielding call:

```mare
    Numbers.will_not_yield -> (i| i)
```
```error
This function call doesn't meet subtyping requirements:
    Numbers.will_not_yield -> (i| i)
            ^~~~~~~~~~~~~~

- it has a yield block:
    Numbers.will_not_yield -> (i| i)
                                 ^~

- but 'Numbers.will_not_yield' has no yields:
  :fun will_not_yield: None
       ^~~~~~~~~~~~~~
```
```error
This yield block parameter will never be received:
    Numbers.will_not_yield -> (i| i)
                               ^

- 'Numbers.will_not_yield' does not yield it:
  :fun will_not_yield: None
       ^~~~~~~~~~~~~~
```

---

It complains when a yield block is not present on a yielding call:

```mare
    Numbers.yield_99
```
```error
This function call doesn't meet subtyping requirements:
    Numbers.yield_99
            ^~~~~~~~

- it has no yield block but 'Numbers.yield_99' does yield:
    yield U64[99]
          ^~~~~~~
```

---

It complains when the yield param type doesn't match a constraint:

```mare
    sum U32 = 0
    Numbers.yield_99 -> (i| j U32 = i)
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    Numbers.yield_99 -> (i| j U32 = i)
                         ^

- it is required here to be a subtype of U64:
    Numbers.yield_99 -> (i| j U32 = i)
                         ^

- it is required here to be a subtype of U32:
    Numbers.yield_99 -> (i| j U32 = i)
                              ^~~

- but the type of the value yielded to this block was U64:
    Numbers.yield_99 -> (i| j U32 = i)
                         ^
```
TODO: Try to remove this redundant error message:
```error
The type of this expression doesn't meet the constraints imposed on it:
    Numbers.yield_99 -> (i| j U32 = i)
                                    ^

- it is required here to be a subtype of U32:
    Numbers.yield_99 -> (i| j U32 = i)
                              ^~~

- but the type of the local variable was U64:
    Numbers.yield_99 -> (i| j U32 = i)
                         ^
```
