---
pass: types
---

It analyzes a simple system of types.

```savi
:trait box _Describable
  :fun describe String

:module Example1(A _Describable)
  :fun example(a A, cond Bool)
    x String = a.describe
    y = if cond ("string" | b"bytes")
```
```types.type_variables_list Example1.example
T'A'^1
  <: (_Describable & box)
  :module Example1(A _Describable)
                     ^~~~~~~~~~~~
~~~
T'return'2
  :> T'y'7'aliased
      y = if cond ("string" | b"bytes")
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

---

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
T'return'2
  <: (String & K'@'1->val)
    :var field String
               ^~~~~~
  :> T'field'^1'aliased
    :var field String
         ^~~~~
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
T'return'2
  <: (String & K'@'1->val)
    :var field String
               ^~~~~~
  :> T'field'^1'aliased
    :var field String
         ^~~~~

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
T'return'2
  <: (String & K'@'1->val)
    :var field String
               ^~~~~~
  :> T'field'^1
    :var field String
         ^~~~~

T'value'3
  <: (String & val)
    :var field String
               ^~~~~~
```

---

It analyzes an array literal, its elements, and its antecedent.

```savi
:module ArrayExample
  :fun example
    a Array(F64)'val = [1, 2.3]
```
```types.type_variables_list ArrayExample.example
~~~
T'return'2
  :> T'a'3'aliased
      a Array(F64)'val = [1, 2.3]
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~

T'a'3
  := (Array((F64 & val)) & val)
      a Array(F64)'val = [1, 2.3]
        ^~~~~~~~~~~~~~
  :> T'array:group'6'stabilized
      a Array(F64)'val = [1, 2.3]
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~

T'num:1'4
  <: (Numeric & val)
      a Array(F64)'val = [1, 2.3]
                          ^

T'float:2.3'5
  <: ((F64 & val) | (F32 & val))
      a Array(F64)'val = [1, 2.3]
                             ^~~

T'array:group'6
  <: ((Array(T'array:elem'7) & iso) | (Array(T'array:elem'7) & val) | (Array(T'array:elem'7) & ref))
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~

T'array:elem'7
  :> T'num:1'4
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~
  :> T'float:2.3'5
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~
```
