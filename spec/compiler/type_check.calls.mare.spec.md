---
pass: type_check
---

The following types are used in some but not all of the examples below:
```mare
:class Inner
  :new iso

:class Outer
  :prop inner Inner: Inner.new
  :new iso
```

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

---

It complains when calling with an insufficient receiver capability:

```mare
:class FunRefMutate
  :fun ref mutate
```
```mare
    mutatable box = FunRefMutate.new
    mutatable.mutate
```
```error
This function call doesn't meet subtyping requirements:
    mutatable.mutate
              ^~~~~~

- the type FunRefMutate'box isn't a subtype of the required capability of 'ref':
  :fun ref mutate
       ^~~
```

---

It complains with an extra hint when using insufficient capability of @:

```mare
:class FunRefMutateFunReadOnly
  :fun ref mutate: None
  :fun readonly: @mutate
```
```error
This function call doesn't meet subtyping requirements:
  :fun readonly: @mutate
                  ^~~~~~

- the type FunRefMutateFunReadOnly'box isn't a subtype of the required capability of 'ref':
  :fun ref mutate: None
       ^~~

- this would be possible if the calling function were declared as `:fun ref`:
  :fun readonly: @mutate
   ^~~
```

---

It complains on auto-recovery for a val method receiver:

```mare
:class FunValImmutableString
  :prop string String'ref: String.new
  :fun val immutable_string: @string
  :new iso
```
```mare
    wrapper FunValImmutableString'iso = FunValImmutableString.new
    string String'val = wrapper.immutable_string
```
```error
This function call doesn't meet subtyping requirements:
    string String'val = wrapper.immutable_string
                                ^~~~~~~~~~~~~~~~

- the function's required receiver capability is `val` but only a `ref` or `box` function can be auto-recovered:
  :fun val immutable_string: @string
       ^~~

- auto-recovery was attempted because the receiver's type is FunValImmutableString'iso:
    wrapper FunValImmutableString'iso = FunValImmutableString.new
            ^~~~~~~~~~~~~~~~~~~~~~~~~
```

---

It complains on auto-recovery when the argument is not sendable:

```mare
    outer_iso Outer'iso = Outer.new
    inner_iso Inner'iso = Inner.new
    inner_ref Inner'ref = Inner.new

    outer_iso.inner = --inner_iso // okay; argument is sendable
    outer_iso.inner = inner_ref   // not okay
```
```error
This function call won't work unless the receiver is ephemeral; it must either be consumed or be allowed to be auto-recovered. Auto-recovery didn't work for these reasons:
    outer_iso.inner = inner_ref   // not okay
              ^~~~~

- the argument (when aliased) has a type of Inner, which isn't sendable:
    outer_iso.inner = inner_ref   // not okay
                      ^~~~~~~~~
```

---

It complains on auto-recovery of a property setter whose return is used:

```mare
    outer_trn Outer'trn = Outer.new
    outer_trn.inner = Inner.new         // okay; return value is unused
    inner = outer_trn.inner = Inner.new // not okay
```
```error
This function call won't work unless the receiver is ephemeral; it must either be consumed or be allowed to be auto-recovered. Auto-recovery didn't work for these reasons:
    inner = outer_trn.inner = Inner.new // not okay
                      ^~~~~

- the return type Inner isn't sendable and the return value is used (the return type wouldn't matter if the calling side entirely ignored the return value):
  :prop inner Inner: Inner.new
              ^~~~~
```

---

It complains when calling a function with too many or too few arguments:

```mare
    @example(1, 2)
    @example(1, 2, 3)
    @example(1, 2, 3, 4)
    @example(1, 2, 3, 4, 5)
    @example(1, 2, 3, 4, 5, U8[6])

  :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
```
```error
This function call doesn't meet subtyping requirements:
    @example(1, 2)
     ^~~~~~~

- the call site has too few arguments:
    @example(1, 2)
     ^~~~~~~

- the function requires at least 3 arguments:
  :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
               ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```
```error
This function call doesn't meet subtyping requirements:
    @example(1, 2, 3, 4, 5, U8[6])
     ^~~~~~~

- the call site has too many arguments:
    @example(1, 2, 3, 4, 5, U8[6])
     ^~~~~~~

- the function allows at most 5 arguments:
  :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
               ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```
