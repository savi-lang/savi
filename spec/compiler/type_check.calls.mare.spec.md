---
pass: type_check
---

It complains when calling on types without that function:

```mare
:trait Fooable
  :fun foo: "foo"

:class Barable
  :fun bar: "bar"

:primitive Bazable
  :fun baz: "baz"
```
```mare
    object (Fooable | Barable | Bazable) = Barable.new
    object.bar
```
```error
The 'bar' function can't be called on this local variable:
    object.bar
           ^~~

- this local variable may have type Bazable:
    object (Fooable | Barable | Bazable) = Barable.new
           ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- Bazable has no 'bar' function:
:primitive Bazable
           ^~~~~~~

- maybe you meant to call the 'baz' function:
  :fun baz: "baz"
       ^~~

- this local variable may have type Fooable:
    object (Fooable | Barable | Bazable) = Barable.new
           ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- Fooable has no 'bar' function:
:trait Fooable
       ^~~~~~~
```

---

It suggests a similarly named function when found:

```mare
:primitive SomeHFunctions
  :fun hey
  :fun hell
  :fun hello_world
```
```mare
    SomeHFunctions.hello
```
```error
The 'hello' function can't be called on this singleton value for this type:
    SomeHFunctions.hello
                   ^~~~~

- SomeHFunctions has no 'hello' function:
:primitive SomeHFunctions
           ^~~~~~~~~~~~~~

- maybe you meant to call the 'hell' function:
  :fun hell
       ^~~~
```

---

It suggests a similarly named function (without '!') when found:

```mare
:primitive HelloNotPartial
  :fun hello
```
```mare
    HelloNotPartial.hello!
```
```error
The 'hello!' function can't be called on this singleton value for this type:
    HelloNotPartial.hello!
                    ^~~~~~

- HelloNotPartial has no 'hello!' function:
:primitive HelloNotPartial
           ^~~~~~~~~~~~~~~

- maybe you meant to call 'hello' (without '!'):
  :fun hello
       ^~~~~
```

---

It suggests a similarly named function (with '!') when found:

```mare
:primitive HelloPartial
  :fun hello!
```
```mare
    HelloPartial.hello
```
```error
The 'hello' function can't be called on this singleton value for this type:
    HelloPartial.hello
                 ^~~~~

- HelloPartial has no 'hello' function:
:primitive HelloPartial
           ^~~~~~~~~~~~

- maybe you meant to call 'hello!' (with a '!'):
  :fun hello!
       ^~~~~~
```
