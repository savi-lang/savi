---
pass: load
---

It complains when the declaration name is totally unknown.

```savi
:bogus bogus
```
```error
There is no declarator named `bogus` known within this file scope:
:bogus bogus
 ^~~~~

- did you forget to add a package dependency?
```

---

It offers a spelling correction when the name is slightly wrong.

```savi
:classy bogus
```
```error
There is no declarator named `classy` known within this file scope:
:classy bogus
 ^~~~~~

- did you mean `:class`?:
:declarator class
            ^~~~~
```

---

It complains when the declarator is not in the right context.

```savi
:module Example
  :yields String for U64
```
```error
This declaration didn't match any known declarator:
  :yields String for U64
  ^~~~~~~~~~~~~~~~~~~~~~

- This declarator didn't match:
:declarator yields
            ^~~~~~

- it can only be used within a `function` context:
  :context function
           ^~~~~~~~

- This declarator didn't match:
:declarator yields
            ^~~~~~

- it can only be used within a `function` context:
  :context function
           ^~~~~~~~

- This declarator didn't match:
:declarator yields
            ^~~~~~

- it can only be used within a `function` context:
  :context function
           ^~~~~~~~
```

---

It complains when a `TypeOrTypeList` term is not accepted by the declarator.

```savi
:module Example
  :fun call(message String) U64
    :yields "bogus"
```
```error
These declaration terms didn't match any known declarator:
    :yields "bogus"
    ^~~~~~~~~~~~~~~

- This declarator didn't match:
:declarator yields
            ^~~~~~

- this term was not acceptable:
    :yields "bogus"
            ^~~~~~~

- an algebraic type or parenthesized group of algebraic types would be accepted:
  :term out TypeOrTypeList
  ^~~~~~~~~~~~~~~~~~~~~~~~

- This declarator didn't match:
:declarator yields
            ^~~~~~

- this term was not acceptable:
    :yields "bogus"
            ^~~~~~~

- the keyword `for` would be accepted:
  :keyword for
  ^~~~~~~~~~~~

- This declarator didn't match:
:declarator yields
            ^~~~~~

- this term was not acceptable:
    :yields "bogus"
            ^~~~~~~

- an algebraic type or parenthesized group of algebraic types would be accepted:
  :term out TypeOrTypeList
  ^~~~~~~~~~~~~~~~~~~~~~~~
```

---

It complains when a `NameMaybeWithParams` term is not accepted by the declarator.

```savi
:module Example
  :fun call(Array(U8)) U64
```
```error
These declaration terms didn't match any known declarator:
  :fun call(Array(U8)) U64
  ^~~~~~~~~~~~~~~~~~~~~~~~

- This declarator didn't match:
:declarator fun
            ^~~

- this term was not acceptable:
  :fun call(Array(U8)) U64
       ^~~~~~~~~~~~~~~

- any of these would be accepted: `non`:
  :term cap enum (non)
  ^~~~~~~~~~~~~~~~~~~~

- a name with an optional parenthesized list of parameter specifiers (each parameter having at least a name and possibly a type and/or default argument) would be accepted:
  :term name_and_params NameMaybeWithParams
  ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- This declarator didn't match:
:declarator fun
            ^~~

- this term was not acceptable:
  :fun call(Array(U8)) U64
       ^~~~~~~~~~~~~~~

- any of these would be accepted: `iso`, `val`, `ref`, `box`, `tag`, `non`:
  :term cap enum (iso, val, ref, box, tag, non)
  ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- a name with an optional parenthesized list of parameter specifiers (each parameter having at least a name and possibly a type and/or default argument) would be accepted:
  :term name_and_params NameMaybeWithParams
  ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

---

It complains when a body is not within any declaration that accepts it.

```savi
:class NoBodyForMePlease
  "here's a body for ya"
```
```error
This body wasn't accepted by any open declaration:
  "here's a body for ya"
  ^~~~~~~~~~~~~~~~~~~~~~
```

---

It complains when a body is given to a declaration that already accepted one.

```savi
  :fun one_body
    "here's the one body; pretty standard stuff"

  :fun one_body_with_yield
    :yields String
    "here's the one body, after a yield; that's okay"

  :fun two_bodies
    "here's the first of two bodies"
    :yields String
    "here's the second of two bodies; huh?"
```
```error
This declaration already accepted a body here:
    "here's the first of two bodies"
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- so it can't accept this additional body here:
    "here's the second of two bodies; huh?"
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```
```error
This body wasn't accepted by any open declaration:
    "here's the second of two bodies; huh?"
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```
