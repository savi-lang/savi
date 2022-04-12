---
pass: type_check
---

It complains when getting a function address from a non-single type:

```savi
:module Foo1
  :fun foo: "foo"

:module Foo2
  :fun bar: "bar"
```
```savi
    object (Foo1 | Foo2) = Foo1
    static_address_of_function object.foo
```
```error
A function address can only be taken from a single explicit type:
    static_address_of_function object.foo
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- (Foo1 | Foo2) is not a single type:
    object (Foo1 | Foo2) = Foo1
           ^~~~~~~~~~~~~
```

---

It complains when getting a function address from a non-existent function:

```savi
    static_address_of_function None.bogus
```
```error
The function trying to be addressed here does not exist:
    static_address_of_function None.bogus
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- None has no function named "bogus":
:module None
        ^~~~
```

---

It complains when getting a function address from a non-`non` function:

```savi
    static_address_of_function @foo

  :fun tag foo: "Foo"
```
```error
A function address can only be taken when the cap is "non":
    static_address_of_function @foo
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- this function has a cap of "tag":
  :fun tag foo: "Foo"
       ^~~
```

---

It complains when getting a function address from a function with no body:

```savi
:trait Fooable
  :fun non foo String
```
```savi
    static_address_of_function Fooable.foo
```
```error
A function address can only be taken from a function with a body:
    static_address_of_function Fooable.foo
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- this function has no body:
  :fun non foo String
           ^~~
```
