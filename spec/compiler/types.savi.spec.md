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
  :> T'describe'6
      x String = a.describe
      ^~~~~~~~~~~~~~~~~~~~~

T'describe'6
  :> T'a'3.describe
      x String = a.describe
                 ^~~~~~~~~~

T'y'7
  :> ((String & val) | (Bytes & val))
      y = if cond ("string" | b"bytes")
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~
  (Bool & val) :> T'cond'4
      y = if cond ("string" | b"bytes")
             ^~~~

  (Bool & val) :> (Bool & val)
      y = if cond ("string" | b"bytes")
          ^~
```
