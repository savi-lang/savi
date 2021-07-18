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

T'return'3
  :> T'y'8'aliased
      y = if cond ("string" | b"bytes")
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

T'a'4
  <: T'A'^1
    :fun example(a A, cond Bool)
                   ^

T'cond'5
  <: (Bool & val)
    :fun example(a A, cond Bool)
                           ^~~~

T'x'6
  := (String & val)
      x String = a.describe
        ^~~~~~
  :> T'describe'7'stabilized
      x String = a.describe
      ^~~~~~~~~~~~~~~~~~~~~

T'describe'7
  :> T'a'4'aliased.describe
      x String = a.describe
                 ^~~~~~~~~~

T'y'8
  :> ((String & val) | (Bytes & val))
      y = if cond ("string" | b"bytes")
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~
  (Bool & val) :> T'cond'5'aliased
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
  :> T'value'4
    :var field String
         ^~~~~
  :> T'value'4
    :var field String
         ^~~~~
~~~
T'@'1
  := (ExampleField & K'@'2)
    :var field String
     ^~~

T'return'3
  <: (String & T'@'1->val)
    :var field String
               ^~~~~~
  :> T'field'^1'aliased
    :var field String
         ^~~~~

```
```types.type_variables_list ExampleField.field=
T'field'^1
  :> T'value'4
    :var field String
         ^~~~~
  :> T'value'4
    :var field String
         ^~~~~
~~~
T'@'1
  := (ExampleField & K'@'2)
    :var field String
     ^~~

T'return'3
  <: (String & T'@'1->val)
    :var field String
               ^~~~~~
  :> T'field'^1'aliased
    :var field String
         ^~~~~

T'value'4
  <: (String & val)
    :var field String
               ^~~~~~

```
```types.type_variables_list ExampleField.field<<=
T'field'^1
  :> T'value'4
    :var field String
         ^~~~~
  :> T'value'4
    :var field String
         ^~~~~
~~~
T'@'1
  := (ExampleField & K'@'2)
    :var field String
     ^~~

T'return'3
  <: (String & T'@'1->val)
    :var field String
               ^~~~~~
  :> T'field'^1
    :var field String
         ^~~~~

T'value'4
  <: (String & val)
    :var field String
               ^~~~~~

```

---

It analyzes an array literal, its elements, and its antecedent.

```savi
:primitive ArrayExample
  :fun example
    a Array(F64)'val = [1, 2.3]
```
```types.type_variables_list ArrayExample.example
~~~
T'@'1
  := (ArrayExample & K'@'2)
    :fun example
     ^~~

T'return'3
  :> T'a'4'aliased
      a Array(F64)'val = [1, 2.3]
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~

T'a'4
  := (Array((F64 & val)) & val)
      a Array(F64)'val = [1, 2.3]
        ^~~~~~~~~~~~~~
  :> T'array:group'7'stabilized
      a Array(F64)'val = [1, 2.3]
      ^~~~~~~~~~~~~~~~~~~~~~~~~~~

T'num:1'5
  <: (Numeric & val)
      a Array(F64)'val = [1, 2.3]
                          ^

T'float:2.3'6
  <: ((F64 & val) | (F32 & val))
      a Array(F64)'val = [1, 2.3]
                             ^~~

T'array:group'7
  <: ((Array(T'array:elem'8) & iso) | (Array(T'array:elem'8) & val) | (Array(T'array:elem'8) & ref))
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~

T'array:elem'8
  :> T'num:1'5
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~
  :> T'float:2.3'6
      a Array(F64)'val = [1, 2.3]
                         ^~~~~~~~
```
