---
pass: caps
---

It analyzes a simple system of caps.

```savi
:module Example1
  :fun example(cond Bool'val)
    if cond ("foo" | String)
```
```caps_graph Example1.example
~~~
K:@:1

K:return:2
  :> val
      if cond ("foo" | String)
               ^~~~~
  :> non
      if cond ("foo" | String)
                       ^~~~~~

K:cond:3
  <: val
      if cond ("foo" | String)
         ^~~~
  :> val
    :fun example(cond Bool'val)
                      ^~~~~~~~

K:choice:result:4
  <: K:return:2
      if cond ("foo" | String)
      ^~~~~~~~~~~~~~~~~~~~~~~~
  :> val
      if cond ("foo" | String)
               ^~~~~
  :> non
      if cond ("foo" | String)
                       ^~~~~~
```
