---
pass: namespace
---

It complains when a type has the same name as a built-in type.

```savi
:class String
```
```error
This type's name conflicts with a mandatory built-in type:
:class String
       ^~~~~~

- the built-in type is defined here:
:class val String
           ^~~~~~
```

---

It won't complain about sharing the name of a private built-in type.

```savi
:module _FFI // also defined in core Savi, but private, so no conflict here
```

---

It complains when a function has the same name as another in the same type.

```savi
  :fun same_name: "This is a contentious function!"
  :var same_name: "This is a contentious property!"
  :const same_name: "This is a contentious constant!"
```
```error
This name conflicts with others declared in the same type:
  :fun same_name: "This is a contentious function!"
       ^~~~~~~~~

- a conflicting declaration is here:
  :var same_name: "This is a contentious property!"
       ^~~~~~~~~

- a conflicting declaration is here:
  :const same_name: "This is a contentious constant!"
         ^~~~~~~~~
```

---

It complains when a type name contains an exclamation point.

```savi
:module ExclamationType!
:module GenericExclamationType!(A)
:module Exclamation!.Type
:module GenericExclamation!.Type(A)
```
```error
A type name cannot contain an exclamation point:
:module ExclamationType!
        ^~~~~~~~~~~~~~~~
```
```error
A type name cannot contain an exclamation point:
:module GenericExclamationType!(A)
        ^~~~~~~~~~~~~~~~~~~~~~~
```
```error
A type name cannot contain an exclamation point:
:module Exclamation!.Type
        ^~~~~~~~~~~~~~~~~
```
```error
A type name cannot contain an exclamation point:
:module GenericExclamation!.Type(A)
        ^~~~~~~~~~~~~~~~~~~~~~~~
```
