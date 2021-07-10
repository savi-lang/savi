---
pass: types
---

It analyzes a simple system of types.

```mare
:primitive Example1
  :fun example
    x String = "value"
```
```types.type_variables_list Example1.example
T'@'1
  := (Example1 & K'@'2)
    :fun example
     ^~~

T'x'3
  := (String & val)
      x String = "value"
        ^~~~~~
  |= (String & val)
      x String = "value"
      ^~~~~~~~~~~~~~~~~~
```
