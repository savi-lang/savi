---
pass: import
---

It complains when the declaration name is totally unknown.

```savi
:bogus bogus
```
```error
There is no declarator named `bogus` known within this file scope:
:bogus bogus
 ^~~~~

- did you forget to import a library?
```

---

It offers a spelling correction when the name is slightly wrong.

```savi
:inpork bogus
```
```error
There is no declarator named `inpork` known within this file scope:
:inpork bogus
 ^~~~~~

- did you mean `:import`?:
:declarator import
            ^~~~~~
```

---

It complains when the declarator is not in the right context.

```savi
:primitive Example
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

It complains when the declaration's terms are not accepted by the declarators.

```savi
:primitive Example
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
