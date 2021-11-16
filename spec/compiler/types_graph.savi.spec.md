---
pass: types_graph
---

It analyzes a simple system of types.

```savi
:trait box _Describable
  :fun describe String

:module Example1(A _Describable)
  :fun example(a A, cond Bool)
    x String = a.describe(80)
    y = if cond ("string" | b"bytes")
```
```types_graph Example1.example
α'A'^1
  <: _Describable
  :module Example1(A _Describable)
                     ^~~~~~~~~~~~
~~~
α'@'1
  <: Example1(α'A'^1)
    :fun example(a A, cond Bool)
         ^~~~~~~

α'return'2
  :> String
      y = if cond ("string" | b"bytes")
                   ^~~~~~~~
  :> Bytes
      y = if cond ("string" | b"bytes")
                              ^~~~~~~~

α'a'3
  <: α'A'^1
    :fun example(a A, cond Bool)
                   ^

α'cond'4
  <: Bool
    :fun example(a A, cond Bool)
                           ^~~~
  <: Bool
      y = if cond ("string" | b"bytes")
             ^~~~

α'x'5
  <: String
      x String = a.describe(80)
        ^~~~~~
  :> String
      x String = a.describe(80)
        ^~~~~~
  :> α'describe'8
      x String = a.describe(80)
      ^~~~~~~~~~~~~~~~~~~~~~~~~

α'num:80'6
  <: Numeric
      x String = a.describe(80)
                            ^~
  <: α'describe(0)'7
      x String = a.describe(80)
                            ^~

α'describe(0)'7
  goes to param index 0 of this call:
      x String = a.describe(80)
                 ^~~~~~~~~~
  will be further constrained after resolving:
    - α'a'3

α'describe'8
  comes from the result of this call:
      x String = a.describe(80)
                 ^~~~~~~~~~
  <: String
      x String = a.describe(80)
        ^~~~~~
  will be further constrained after resolving:
    - α'a'3

α'y'9
  <: α'return'2
      y = if cond ("string" | b"bytes")
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  :> String
      y = if cond ("string" | b"bytes")
                   ^~~~~~~~
  :> Bytes
      y = if cond ("string" | b"bytes")
                              ^~~~~~~~

α'choice:result'10
  <: α'y'9
      y = if cond ("string" | b"bytes")
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  :> String
      y = if cond ("string" | b"bytes")
                   ^~~~~~~~
  :> Bytes
      y = if cond ("string" | b"bytes")
                              ^~~~~~~~
```

---

It analyzes the getter, setter, and displacement methods of a field.

```savi
:class ExampleField
  :var field String
```
```types_graph ExampleField.field
α'field'^1
  <: String
    :var field String
               ^~~~~~
  <: α'return'2
    :var field String
         ^~~~~
  <: α'return'2
    :var field String
         ^~~~~
  <: α'return'2
    :var field String
         ^~~~~
  :> String
    :var field String
               ^~~~~~
~~~
α'@'1
  <: ExampleField
    :var field String
         ^~~~~

α'return'2
  <: String
    :var field String
               ^~~~~~
  :> String
    :var field String
               ^~~~~~
```
```types_graph ExampleField.field=
α'field'^1
  <: String
    :var field String
               ^~~~~~
  <: α'return'2
    :var field String
         ^~~~~
  <: α'return'2
    :var field String
         ^~~~~
  <: α'return'2
    :var field String
         ^~~~~
  :> String
    :var field String
               ^~~~~~
~~~
α'@'1
  <: ExampleField
    :var field String
         ^~~~~

α'return'2
  <: String
    :var field String
               ^~~~~~
  :> String
    :var field String
               ^~~~~~

α'value'3
  <: String
    :var field String
               ^~~~~~
  <: α'field'^1
    :var field String
         ^~~~~
```
```types_graph ExampleField.field<<=
α'field'^1
  <: String
    :var field String
               ^~~~~~
  <: α'return'2
    :var field String
         ^~~~~
  <: α'return'2
    :var field String
         ^~~~~
  <: α'return'2
    :var field String
         ^~~~~
  :> String
    :var field String
               ^~~~~~
~~~
α'@'1
  <: ExampleField
    :var field String
         ^~~~~

α'return'2
  <: String
    :var field String
               ^~~~~~
  :> String
    :var field String
               ^~~~~~

α'value'3
  <: String
    :var field String
               ^~~~~~
  <: α'field'^1
    :var field String
         ^~~~~
```

---

It analyzes an array literal, its elements, and its antecedent.

```savi
:module ArrayExample
  :fun example
    a Array(F64)'val = [1, 2.3]
```
```types_graph ArrayExample.example
~~~
α'@'1
  <: ArrayExample
    :fun example
         ^~~~~~~

α'return'2
  :> Array(F64)
      a Array(F64)'val = [1, 2.3]
        ^~~~~~~~~~~~~~

α'a'3
  <: Array(F64)
      a Array(F64)'val = [1, 2.3]
        ^~~~~~~~~~~~~~
  <: α'return'2
      a Array(F64)'val = [1, 2.3]
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~
  :> Array(F64)
      a Array(F64)'val = [1, 2.3]
        ^~~~~~~~~~~~~~

α'num:1'4
  <: Numeric
      a Array(F64)'val = [1, 2.3]
                          ^
  <: α'array:elem'7
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~

α'float:2.3'5
  <: (F64 | F32)
      a Array(F64)'val = [1, 2.3]
                             ^~~
  <: α'array:elem'7
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~

α'array:group'6
  <: Array(α'array:elem'7)
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~
  <: α'a'3
      a Array(F64)'val = [1, 2.3]
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~

α'array:elem'7
```
