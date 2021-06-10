---
pass: type_check
---

It allows assigning from a variable with its refined type:

```mare
    x val = "example"
    if (x <: String) (
      y String = x
    )
```

---

It allows assigning from a parameter with its refined type:

```mare
    @refine("example")

  :fun refine(x val)
    if (x <: String) (
      y String = x
    )
```

---

It complains when the match type isn't a subtype of the original:

```mare
    @refine("example")

  :fun refine(x String)
    if (x <: Numeric) x.u8
```
```error
This type check will never match:
    if (x <: Numeric) x.u8
        ^~~~~~~~~~~~

- the runtime match type, ignoring capabilities, is Numeric'any:
    if (x <: Numeric) x.u8
             ^~~~~~~

- which does not intersect at all with String:
  :fun refine(x String)
                ^~~~~~
```

---

It complains when a check would require runtime knowledge of capabilities:

```mare
    @example("example")

  :fun example(x (String'val | String'ref))
    if (x <: String'ref) (
      x << "..."
    )
```
```error
This type check could violate capabilities:
    if (x <: String'ref) (
        ^~~~~~~~~~~~~~~

- the runtime match type, ignoring capabilities, is String'any:
    if (x <: String'ref) (
             ^~~~~~~~~~

- if it successfully matches, the type will be (String | String'ref):
  :fun example(x (String'val | String'ref))
                 ^~~~~~~~~~~~~~~~~~~~~~~~~

- which is not a subtype of String'ref:
    if (x <: String'ref) (
             ^~~~~~~~~~
```

---

It can also refine a type parameter within a choice body:

```mare
:trait Sizeable
  :fun size USize

:class Container(A)
  :let _value A
  :new (@_value)
  :fun ref value_size
    if (A <: Sizeable'val) @_value.size
```
```mare
    Container(String).new("example").value_size ::type=> (USize | None)
```
