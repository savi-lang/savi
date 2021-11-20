---
pass: caps
---

It analyzes a simple system of caps.

```savi
:module Example1
  :fun example
    if True ("foo" | String)
```
```caps_graph Example1.example
~~~
K:@:1

K:return:2
  :> val
      if True ("foo" | String)
               ^~~~~
  :> non
      if True ("foo" | String)
                       ^~~~~~

K:choice:result:3
  <: K:return:2
      if True ("foo" | String)
      ^~~~~~~~~~~~~~~~~~~~~~~~
  :> val
      if True ("foo" | String)
               ^~~~~
  :> non
      if True ("foo" | String)
                       ^~~~~~
```
