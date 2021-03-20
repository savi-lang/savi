---
pass: type_check
---

It complains when too many type arguments are provided:

```mare
:class Generic2 (P1, P2)
```
```mare
    Generic2(String, String, String, String)
```
```error
This type qualification has too many type arguments:
    Generic2(String, String, String, String)
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- at most 2 type arguments were expected:
:class Generic2 (P1, P2)
                ^~~~~~~~

- this is an excessive type argument:
    Generic2(String, String, String, String)
                             ^~~~~~

- this is an excessive type argument:
    Generic2(String, String, String, String)
                                     ^~~~~~
```

---

It complains when too few type arguments are provided:

```mare
:class Generic3 (P1, P2, P3)
```
```mare
    Generic3(String)
```
```error
This type qualification has too few type arguments:
    Generic3(String)
    ^~~~~~~~~~~~~~~~

- at least 3 type arguments were expected:
:class Generic3 (P1, P2, P3)
                ^~~~~~~~~~~~

- this additional type parameter needs an argument:
:class Generic3 (P1, P2, P3)
                     ^~

- this additional type parameter needs an argument:
:class Generic3 (P1, P2, P3)
                         ^~
```

---

It complains when no type arguments are provided and some are expected:

```mare
:class GenericNeedsTypeArgs (P1, P2)
```
```mare
    GenericNeedsTypeArgs
```
```error
This type needs to be qualified with type arguments:
    GenericNeedsTypeArgs
    ^~~~~~~~~~~~~~~~~~~~

- these type parameters are expecting arguments:
:class GenericNeedsTypeArgs (P1, P2)
                            ^~~~~~~~
```

---

It complains when a type argument doesn't satisfy the bound:

```mare
:class GenericSendable (P1 send)
```
```mare
    GenericSendable(String'ref)
```
```error
This type argument won't satisfy the type parameter bound:
    GenericSendable(String'ref)
                    ^~~~~~~~~~

- the type parameter bound is {iso, val, tag, non}:
:class GenericSendable (P1 send)
                           ^~~~

- the type argument is String'ref:
    GenericSendable(String'ref)
                    ^~~~~~~~~~
```

---

It can call the constructor of a type parameter:

```mare
    ConstructingGeneric(ConstructableClass).construct ::type=> ConstructableClass
```
```mare
:trait ConstructableTrait
  :new (number USize)

:class ConstructableClass
  :prop number USize
  :new (@number)

:class ConstructingGeneric (A ConstructableTrait)
  :fun non construct A
    A.new(99)
```
