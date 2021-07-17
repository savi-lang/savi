---
pass: types
---

It analyzes a simple system of types.

```savi
:trait box _Describable
  :fun describe String

:primitive Example1(A _Describable)
  :fun example(a A, cond Bool)
    x String = a.describe
    y = if cond ("string" | b"bytes")
```
```types.type_variables_list Example1.example
T'A'^1
  <: (_Describable & box)
  :primitive Example1(A _Describable)
                        ^~~~~~~~~~~~
~~~
T'@'1
  := (Example1(T'A'^1) & K'@'2)
    :fun example(a A, cond Bool)
     ^~~

T'a'3
  <: T'A'^1
    :fun example(a A, cond Bool)
                   ^

T'cond'4
  <: (Bool & val)
    :fun example(a A, cond Bool)
                           ^~~~

T'x'5
  := (String & val)
      x String = a.describe
        ^~~~~~
  :> T'describe'6'stabilized
      x String = a.describe
      ^~~~~~~~~~~~~~~~~~~~~

T'describe'6
  :> T'a'3'aliased.describe
      x String = a.describe
                 ^~~~~~~~~~

T'y'7
  :> ((String & val) | (Bytes & val))
      y = if cond ("string" | b"bytes")
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~
  (Bool & val) :> T'cond'4'aliased
      y = if cond ("string" | b"bytes")
             ^~~~

  (Bool & val) :> (Bool & val)
      y = if cond ("string" | b"bytes")
          ^~
```

It analyzes the getter, setter, and displacement methods of a field.

```savi
:class ExampleField
  :var field String
```
```types.type_variables_list ExampleField.field
T'field'^1
  :> T'value'3
    :var field String
         ^~~~~
  :> T'value'3
    :var field String
         ^~~~~
~~~
T'@'1
  := (ExampleField & K'@'2)
    :var field String
     ^~~
```
```types.type_variables_list ExampleField.field=
T'field'^1
  :> T'value'3
    :var field String
         ^~~~~
  :> T'value'3
    :var field String
         ^~~~~
~~~
T'@'1
  := (ExampleField & K'@'2)
    :var field String
     ^~~

T'value'3
  <: (String & val)
    :var field String
               ^~~~~~
```
```types.type_variables_list ExampleField.field<<=
T'field'^1
  :> T'value'3
    :var field String
         ^~~~~
  :> T'value'3
    :var field String
         ^~~~~
~~~
T'@'1
  := (ExampleField & K'@'2)
    :var field String
     ^~~

T'value'3
  <: (String & val)
    :var field String
               ^~~~~~
```
